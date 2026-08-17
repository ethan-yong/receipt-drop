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
import android.view.WindowManager
import android.widget.GridLayout
import android.widget.TextView
import com.receiptdrop.receipt_drop.R
import java.util.Locale
import java.util.UUID

/**
 * Overlay UI layer: a small rounded card shown via [WindowManager] on top of
 * whatever app is currently active, offering the app's real category set for
 * a detected payment. Never opens the Flutter Activity and never uses a
 * full-screen intent. On category tap, durably queues the choice via
 * [PaymentEventQueueStore] for Flutter to pick up later — this service does
 * not touch Drift/Supabase itself.
 */
class PaymentOverlayService : Service() {

    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private val timeoutHandler = Handler(Looper.getMainLooper())
    private var timeoutRunnable: Runnable? = null

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

        val payment = ParsedPayment(
            merchantRaw = intent.getStringExtra(EXTRA_MERCHANT) ?: "",
            amountMyr = intent.getDoubleExtra(EXTRA_AMOUNT, 0.0),
            sourcePackage = intent.getStringExtra(EXTRA_SOURCE_PACKAGE) ?: "",
            notificationKey = intent.getStringExtra(EXTRA_NOTIFICATION_KEY),
            postedAtEpochMs = intent.getLongExtra(EXTRA_POSTED_AT, System.currentTimeMillis()),
            parserId = intent.getStringExtra(EXTRA_PARSER_ID) ?: "",
        )
        val fingerprint = intent.getStringExtra(EXTRA_FINGERPRINT) ?: ""

        // Single-card-at-a-time: drop any previously shown overlay first.
        removeCurrentView("replaced")
        showOverlay(payment, fingerprint)

        return START_NOT_STICKY
    }

    private fun showOverlay(payment: ParsedPayment, fingerprint: String) {
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        windowManager = wm

        val view = LayoutInflater.from(this).inflate(R.layout.overlay_payment_card, null)
        view.findViewById<TextView>(R.id.overlay_merchant).text = payment.merchantRaw
        view.findViewById<TextView>(R.id.overlay_amount).text =
            String.format(Locale.US, "RM %.2f", payment.amountMyr)

        val grid = view.findViewById<GridLayout>(R.id.overlay_category_grid)
        for ((label, emoji) in CATEGORIES) {
            grid.addView(buildCategoryChip(label, emoji) { onCategoryPicked(label, payment, fingerprint) })
        }

        view.findViewById<TextView>(R.id.overlay_not_now).setOnClickListener {
            dismissOverlay("not_now")
        }

        // WindowManager.LayoutParams has no margin concept — the window
        // itself spans full width; horizontal insets are applied via
        // layout_margin on the card's LinearLayout inside the transparent
        // FrameLayout wrapper in overlay_payment_card.xml instead.
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
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            overlayType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.BOTTOM
            y = dp(24)
        }

        view.alpha = 0f
        view.translationY = dp(40).toFloat()

        wm.addView(view, params)
        overlayView = view

        view.animate()
            .alpha(1f)
            .translationY(0f)
            .setDuration(220)
            .start()

        PaymentLogger.overlayShown(payment)

        val runnable = Runnable { dismissOverlay("timeout") }
        timeoutRunnable = runnable
        timeoutHandler.postDelayed(runnable, AUTO_DISMISS_MS)
    }

    private fun buildCategoryChip(label: String, emoji: String, onClick: () -> Unit): TextView {
        return TextView(this).apply {
            text = "$emoji $label"
            textSize = 13f
            setPadding(dp(12), dp(8), dp(12), dp(8))
            setBackgroundResource(R.drawable.overlay_chip_bg)
            setTextColor(0xFF2E2717.toInt())
            isClickable = true
            isFocusable = true
            val lp = GridLayout.LayoutParams()
            lp.setMargins(dp(4), dp(4), dp(4), dp(4))
            layoutParams = lp
            setOnClickListener { onClick() }
        }
    }

    private fun onCategoryPicked(category: String, payment: ParsedPayment, fingerprint: String) {
        cancelTimeout()
        PaymentLogger.categorySelected(category, payment)

        val event = QueuedPaymentEvent(
            id = UUID.randomUUID().toString(),
            merchantRaw = payment.merchantRaw,
            amountMyr = payment.amountMyr,
            category = category,
            sourcePackage = payment.sourcePackage,
            occurredAtEpochMs = payment.postedAtEpochMs,
            fingerprint = fingerprint,
        )
        PaymentEventQueueStore(applicationContext).enqueue(event)
        PaymentLogger.eventQueued(event.id)

        dismissOverlay("category_selected")
    }

    private fun dismissOverlay(reason: String) {
        cancelTimeout()
        val view = overlayView
        if (view == null) {
            stopSelf()
            return
        }
        view.animate()
            .alpha(0f)
            .translationY(dp(40).toFloat())
            .setDuration(160)
            .withEndAction {
                removeCurrentView(reason)
                stopSelf()
            }
            .start()
    }

    private fun removeCurrentView(reason: String) {
        val view = overlayView ?: return
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
        private const val EXTRA_MERCHANT = "merchant"
        private const val EXTRA_AMOUNT = "amount"
        private const val EXTRA_SOURCE_PACKAGE = "source_package"
        private const val EXTRA_NOTIFICATION_KEY = "notification_key"
        private const val EXTRA_POSTED_AT = "posted_at"
        private const val EXTRA_PARSER_ID = "parser_id"
        private const val EXTRA_FINGERPRINT = "fingerprint"

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

        fun show(context: Context, payment: ParsedPayment, fingerprint: String) {
            val intent = Intent(context, PaymentOverlayService::class.java).apply {
                putExtra(EXTRA_MERCHANT, payment.merchantRaw)
                putExtra(EXTRA_AMOUNT, payment.amountMyr)
                putExtra(EXTRA_SOURCE_PACKAGE, payment.sourcePackage)
                putExtra(EXTRA_NOTIFICATION_KEY, payment.notificationKey)
                putExtra(EXTRA_POSTED_AT, payment.postedAtEpochMs)
                putExtra(EXTRA_PARSER_ID, payment.parserId)
                putExtra(EXTRA_FINGERPRINT, fingerprint)
            }
            context.startService(intent)
        }
    }
}
