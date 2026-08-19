package com.receiptdrop.receipt_drop.paymentdetect

import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.widget.TextView
import com.receiptdrop.receipt_drop.R
import java.util.Locale
import java.util.UUID

/**
 * Overlay UI layer: a small rounded card shown via [WindowManager] on top of
 * whatever app is currently active, offering the app's real category set for
 * a normalized payment/transfer-out result from the Payment Notification LLM
 * pipeline. Never opens the Flutter Activity and never uses a full-screen
 * intent. On category tap, durably queues the choice via
 * [PaymentEventQueueStore] for Flutter to pick up later — this service does
 * not touch Drift/Supabase itself. Category chip set, timeout, animations,
 * and "Not now" are unchanged from the feature's first implementation.
 */
class PaymentOverlayService : Service() {

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private val timeoutHandler = Handler(Looper.getMainLooper())
    private var timeoutRunnable: Runnable? = null

    /** Set for the duration of the exit animation. The card stays on screen
     * and clickable while it plays, so without this a second chip tap (or the
     * timeout firing just as a chip is tapped) queues a second event and
     * restarts the animation from a half-faded state, which reads as a
     * flicker. */
    private var dismissing = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null) {
            stopSelf(startId)
            return START_NOT_STICKY
        }

        if (!Settings.canDrawOverlays(this)) {
            PaymentLogger.overlayDismissed("no_overlay_permission")
            stopSelf(startId)
            return START_NOT_STICKY
        }

        // Single-card-at-a-time: drop any previously shown overlay first.
        removeCurrentView("replaced")
        dismissing = false

        if (intent.getBooleanExtra(EXTRA_UNDERSTANDING_FAILED, false)) {
            showFailedOverlay()
        } else {
            showPaymentOverlay(intent)
        }

        return START_NOT_STICKY
    }

    private fun showPaymentOverlay(intent: Intent) {
        val transactionType = PaymentTransactionType.fromName(intent.getStringExtra(EXTRA_TRANSACTION_TYPE))
        val displayName = intent.getStringExtra(EXTRA_DISPLAY_NAME)
        val amount = intent.getDoubleExtra(EXTRA_AMOUNT, 0.0)
        val currency = intent.getStringExtra(EXTRA_CURRENCY) ?: "MYR"
        val suggestedCategory = intent.getStringExtra(EXTRA_SUGGESTED_CATEGORY)
        val sourcePackage = intent.getStringExtra(EXTRA_SOURCE_PACKAGE) ?: ""
        val postTime = intent.getLongExtra(EXTRA_POST_TIME, System.currentTimeMillis())
        val fingerprint = intent.getStringExtra(EXTRA_FINGERPRINT) ?: ""

        val view = inflateCard()
        view.findViewById<TextView>(R.id.overlay_header).text = when (transactionType) {
            PaymentTransactionType.TRANSFER_OUT -> "Transfer"
            else -> "New payment"
        }
        view.findViewById<TextView>(R.id.overlay_merchant).text = displayName ?: ""
        view.findViewById<TextView>(R.id.overlay_amount).text =
            String.format(Locale.US, "%s %.2f", currency, amount)

        val chips = view.findViewById<FlowLayout>(R.id.overlay_category_chips)
        for ((label, emoji) in CATEGORIES) {
            chips.addView(
                buildCategoryChip(label, emoji, isSuggested = label == suggestedCategory) {
                    onCategoryPicked(label, displayName ?: "", amount, sourcePackage, postTime, fingerprint)
                },
            )
        }

        view.findViewById<TextView>(R.id.overlay_not_now).apply {
            text = "Not now"
            setOnClickListener { dismissOverlay("not_now") }
        }

        showView(view, autoDismissMs = AUTO_DISMISS_MS)
    }

    private fun showFailedOverlay() {
        val view = inflateCard()
        view.findViewById<TextView>(R.id.overlay_header).text = "New payment"
        view.findViewById<TextView>(R.id.overlay_merchant).text = "Could not understand this payment"
        view.findViewById<TextView>(R.id.overlay_amount).text = ""
        view.findViewById<TextView>(R.id.overlay_category_label).visibility = View.GONE
        view.findViewById<FlowLayout>(R.id.overlay_category_chips).visibility = View.GONE
        view.findViewById<TextView>(R.id.overlay_not_now).apply {
            text = "Dismiss"
            setOnClickListener { dismissOverlay("dismiss_failed") }
        }

        showView(view, autoDismissMs = AUTO_DISMISS_MS)
    }

    private fun inflateCard(): View =
        LayoutInflater.from(this).inflate(R.layout.overlay_payment_card, null)

    private fun showView(view: View, autoDismissMs: Long) {
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        windowManager = wm

        // TYPE_APPLICATION_OVERLAY only exists from API 26; minSdk here is
        // 24, so fall back to the deprecated but still-functional TYPE_PHONE
        // on the (in practice negligible, for a personal dev APK) chance of
        // an Android 7/7.1 device.
        val overlayType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        // WindowManager.LayoutParams has no margin concept — the window
        // itself spans full width; horizontal insets are applied via
        // layout_margin on the card's LinearLayout inside the transparent
        // FrameLayout wrapper in overlay_payment_card.xml instead.
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                // An Activity window gets this from the manifest; a window
                // added straight through WindowManager by a Service does not,
                // and silently renders in software. That makes the fade/slide
                // animations below composite on the CPU every frame — the
                // difference between a smooth dismissal and a stuttery one.
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.BOTTOM
            y = dp(24)
        }

        view.alpha = 0f
        view.translationY = dp(24).toFloat()

        wm.addView(view, params)
        overlayView = view

        // withLayer() renders the card into a single hardware layer for the
        // duration instead of re-compositing every child against whatever is
        // behind it on each frame. The card is a stack of overlapping views
        // (background, chips, labels) over an arbitrary host app, which is
        // the case that makes an un-layered alpha animation both expensive
        // and visually muddy.
        view.animate()
            .alpha(1f)
            .translationY(0f)
            .setDuration(200)
            .setInterpolator(DecelerateInterpolator())
            .withLayer()
            .start()

        val runnable = Runnable { dismissOverlay("timeout") }
        timeoutRunnable = runnable
        timeoutHandler.postDelayed(runnable, autoDismissMs)
    }

    private fun buildCategoryChip(label: String, emoji: String, isSuggested: Boolean, onClick: () -> Unit): TextView {
        return TextView(this).apply {
            text = "$emoji $label"
            textSize = 13f
            setPadding(dp(12), dp(8), dp(12), dp(8))
            setBackgroundResource(if (isSuggested) R.drawable.overlay_chip_bg_selected else R.drawable.overlay_chip_bg)
            setTextColor(0xFF2E2717.toInt())
            isClickable = true
            isFocusable = true
            // No leading margin: the first chip on each line then sits flush
            // with the card's text column instead of being nudged inward.
            layoutParams = ViewGroup.MarginLayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { setMargins(0, 0, dp(8), dp(8)) }
            setOnClickListener { onClick() }
        }
    }

    private fun onCategoryPicked(
        category: String,
        displayName: String,
        amount: Double,
        sourcePackage: String,
        postTime: Long,
        fingerprint: String,
    ) {
        if (dismissing) return
        cancelTimeout()
        PaymentLogger.categorySelected(category)

        val event = QueuedPaymentEvent(
            id = UUID.randomUUID().toString(),
            merchantRaw = displayName,
            amountMyr = amount,
            category = category,
            sourcePackage = sourcePackage,
            occurredAtEpochMs = postTime,
            fingerprint = fingerprint,
        )
        PaymentEventQueueStore(applicationContext).enqueue(event)
        PaymentLogger.eventQueued(event.id)

        dismissOverlay("category_selected")
    }

    private fun dismissOverlay(reason: String) {
        if (dismissing) return
        dismissing = true
        cancelTimeout()
        val view = overlayView
        if (view == null) {
            stopSelf()
            return
        }
        view.animate()
            .alpha(0f)
            // A short drop rather than the full slide the card entered on:
            // exiting over a busy host app, a long translucent travel is what
            // reads as "glitchy", so it leaves quickly and mostly by fading.
            .translationY(dp(12).toFloat())
            .setDuration(180)
            .setInterpolator(AccelerateInterpolator())
            .withLayer()
            .withEndAction {
                // A replacement card may have been shown while this exit was
                // still playing; tearing down then would remove the *new*
                // view and stop the service out from under it.
                if (overlayView === view) {
                    removeCurrentView(reason)
                    stopSelf()
                }
            }
            .start()
    }

    private fun removeCurrentView(reason: String) {
        val view = overlayView ?: return
        view.animate().cancel()
        try {
            windowManager?.removeView(view)
        } catch (_: IllegalArgumentException) {
            // Already removed — nothing to do.
        }
        overlayView = null
        PaymentLogger.overlayDismissed(reason)
    }

    private fun cancelTimeout() {
        timeoutRunnable?.let { timeoutHandler.removeCallbacks(it) }
        timeoutRunnable = null
    }

    override fun onDestroy() {
        cancelTimeout()
        removeCurrentView("service_destroyed")
        super.onDestroy()
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    companion object {
        private const val EXTRA_TRANSACTION_TYPE = "transaction_type"
        private const val EXTRA_DISPLAY_NAME = "display_name"
        private const val EXTRA_AMOUNT = "amount"
        private const val EXTRA_CURRENCY = "currency"
        private const val EXTRA_SUGGESTED_CATEGORY = "suggested_category"
        private const val EXTRA_SOURCE_PACKAGE = "source_package"
        private const val EXTRA_POST_TIME = "post_time"
        private const val EXTRA_FINGERPRINT = "fingerprint"
        private const val EXTRA_UNDERSTANDING_FAILED = "understanding_failed"

        private const val AUTO_DISMISS_MS = 12_000L

        // Mirrors assets/config/categories-v1.json / AppColors.categoryEmoji
        // (lib/core/theme/app_colors.dart) — kept in sync manually since the
        // Flutter engine may not be running when this list is needed.
        private val CATEGORIES = listOf(
            "Food & Drink" to "🍽️",
            "Groceries" to "🛒",
            "Transport" to "🚌",
            "Travel" to "✈️",
            "Shopping" to "🛍️",
            "Health & Beauty" to "💊",
            "Others" to "🧾",
        )

        fun show(
            context: Context,
            event: PaymentNotificationEvent,
            understanding: PaymentNotificationUnderstanding,
            suggestedCategory: String?,
            fingerprint: String,
        ) {
            val amount = understanding.amount ?: return
            val intent = Intent(context, PaymentOverlayService::class.java).apply {
                putExtra(EXTRA_TRANSACTION_TYPE, understanding.transactionType.name)
                putExtra(EXTRA_DISPLAY_NAME, understanding.displayName)
                putExtra(EXTRA_AMOUNT, amount)
                putExtra(EXTRA_CURRENCY, understanding.currency)
                putExtra(EXTRA_SUGGESTED_CATEGORY, suggestedCategory)
                putExtra(EXTRA_SOURCE_PACKAGE, event.sourcePackage)
                putExtra(EXTRA_POST_TIME, event.postTime)
                putExtra(EXTRA_FINGERPRINT, fingerprint)
            }
            context.startService(intent)
        }

        /** Minimal, dismiss-only card for a notification that cleared the
         * local heuristic and got a real LLM response, but wasn't
         * actionable (unknown type / no amount / low confidence) — see
         * PaymentNotificationListenerService.handleEvent. Never queues
         * anything. */
        fun showUnderstandingFailed(context: Context, event: PaymentNotificationEvent) {
            val intent = Intent(context, PaymentOverlayService::class.java).apply {
                putExtra(EXTRA_UNDERSTANDING_FAILED, true)
                putExtra(EXTRA_SOURCE_PACKAGE, event.sourcePackage)
            }
            context.startService(intent)
        }
    }
}
