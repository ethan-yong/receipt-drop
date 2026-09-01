package com.receiptdrop.receipt_drop.paymentdetect

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
import java.util.Collections
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Detection layer: receives every notification posted on the device, logs
 * it, runs the generic (non-bank-specific) [FinancialNotificationHeuristic]
 * gate, dedups, and — off the binder thread — calls the Payment
 * Notification LLM pipeline via [PaymentNotificationClient]. No bank-
 * specific regex logic lives here or anywhere in this package; a
 * completely unrecognized package goes through this exact same path.
 */
class PaymentNotificationListenerService : NotificationListenerService() {
    private lateinit var dedupCache: PaymentEventDedupCache
    private lateinit var client: PaymentNotificationClient
    private lateinit var heartbeat: PaymentListenerHeartbeat
    private lateinit var settings: PaymentDetectionSettings
    private var categoryMatcher: CategoryMatcher? = null
    private val executor: ExecutorService = Executors.newCachedThreadPool()

    /** Fingerprints currently being understood. Covers the window between
     * accepting a notification and having a verdict to write to [dedupCache],
     * during which the OS can re-deliver the same notification. */
    private val inFlight: MutableSet<String> = Collections.synchronizedSet(mutableSetOf())

    override fun onCreate() {
        super.onCreate()
        dedupCache = PaymentEventDedupCache(applicationContext)
        client = PaymentNotificationClient()
        heartbeat = PaymentListenerHeartbeat(applicationContext)
        settings = PaymentDetectionSettings(applicationContext)
        categoryMatcher = CategoryMatcher.loadFromAssets(applicationContext)
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        heartbeat.recordConnected()
        Log.d(TAG, "listener connected (notification access granted)")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        heartbeat.recordDisconnected()
        Log.d(TAG, "listener disconnected")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        heartbeat.recordNotificationSeen()

        // Master switch (Profile → "Payment detection"): when off, the listener
        // stays bound (so re-enabling is instant) but does nothing — no LLM
        // call, no overlay. Checked first so a disabled feature is truly inert.
        if (!settings.isEnabled()) return

        val payload = buildPayload(sbn)
        PaymentLogger.notificationReceived(payload)

        if (!FinancialNotificationHeuristic.looksFinancial(payload)) return
        PaymentLogger.financialHeuristicMatched(
            payload,
            FinancialNotificationHeuristic.matchedKeyword(payload),
        )

        val fingerprint = buildFingerprint(payload)
        if (dedupCache.isDuplicate(fingerprint)) {
            PaymentLogger.duplicateIgnored(fingerprint)
            return
        }
        // Only claims the fingerprint for the duration of this attempt. The
        // durable 24h dedup entry is written once there's an actual verdict
        // (see handleEvent) — writing it here meant a single network blip
        // permanently hid that payment, with no retry and nothing shown.
        if (!inFlight.add(fingerprint)) {
            PaymentLogger.duplicateIgnored(fingerprint)
            return
        }

        val event = PaymentNotificationEvent(
            sourcePackage = payload.packageName,
            sourceProvider = PaymentProviderMetadata.lookup(payload.packageName),
            rawText = payload.combinedText,
            postTime = payload.postTime,
            notificationKey = payload.key,
        )

        // onNotificationPosted runs on a binder thread — the LLM call is a
        // network round trip and must not block it. The listener service
        // itself doesn't need to stay alive for this to complete; the
        // executor and its in-flight task are independent of this callback
        // returning.
        val appContext = applicationContext
        executor.execute { handleEvent(appContext, event, fingerprint) }
    }

    private fun handleEvent(context: Context, event: PaymentNotificationEvent, fingerprint: String) {
        try {
            when (val result = understandWithRetry(event)) {
                is PaymentNotificationResult.Success -> {
                    // A verdict, right or wrong — safe to stop reconsidering
                    // this notification for the cache's TTL.
                    dedupCache.remember(fingerprint)
                    handleUnderstood(context, event, fingerprint, result)
                }

                is PaymentNotificationResult.Failure -> {
                    // Infrastructure failure (network/timeout/malformed
                    // response) — log only, no overlay. Interrupting the user
                    // for a connectivity blip is noise, not signal; a genuine
                    // LLM "unknown" verdict is a different, bounded case.
                    //
                    // Deliberately not remembered: this is the absence of a
                    // verdict, so a re-posted notification should get another
                    // chance rather than being silently swallowed for 24h.
                    PaymentLogger.unknownOrLowConfidenceSuppressed(event, result)
                }
            }
        } finally {
            inFlight.remove(fingerprint)
        }
    }

    private fun handleUnderstood(
        context: Context,
        event: PaymentNotificationEvent,
        fingerprint: String,
        result: PaymentNotificationResult.Success,
    ) {
        val understanding = result.understanding
        PaymentLogger.llmCallSucceeded(understanding)

        if (understanding.transactionType == PaymentTransactionType.TRANSFER_IN) {
            // Detected, logged, deduped — but the app's transaction model is
            // expense-only with no income concept, so this is never surfaced
            // further (no overlay, no transaction).
            PaymentLogger.transferInSuppressed(understanding)
            return
        }

        val now = System.currentTimeMillis()
        val stale = isStaleForOverlay(event.postTime, now)

        if (!shouldShowOverlay(understanding)) {
            // A real LLM response that just wasn't actionable (unknown / no
            // amount / low confidence) — log for diagnosis and show a
            // minimal, dismiss-only fallback card rather than staying
            // completely silent, since the system did genuinely attempt to
            // understand this one.
            PaymentLogger.unknownOrLowConfidenceSuppressed(event, result)
            if (!stale) PaymentOverlayService.showUnderstandingFailed(context, event)
            return
        }

        val suggestedCategory = categoryMatcher
            ?.guessWithConfidence(understanding.displayName ?: "", event.rawText)
            ?.category

        if (stale) {
            // The OS held this back (Doze, or the process being suspended)
            // until long after the payment. A card popping up over an
            // unrelated app minutes later reads as a glitch and asks the user
            // to categorize something they've moved on from, so it goes
            // straight to the in-app review queue instead.
            PaymentLogger.staleNotificationDiverted(event, now - event.postTime)
            enqueueForReview(context, event, understanding, suggestedCategory, fingerprint)
            return
        }

        PaymentLogger.overlayShown(understanding)
        PaymentOverlayService.show(context, event, understanding, suggestedCategory, fingerprint)
    }

    private fun enqueueForReview(
        context: Context,
        event: PaymentNotificationEvent,
        understanding: PaymentNotificationUnderstanding,
        suggestedCategory: String?,
        fingerprint: String,
    ) {
        val amount = understanding.amount ?: return
        val queued = QueuedPaymentEvent(
            id = UUID.randomUUID().toString(),
            merchantRaw = understanding.displayName ?: "",
            amountMyr = amount,
            category = null,
            suggestedCategory = suggestedCategory,
            sourcePackage = event.sourcePackage,
            occurredAtEpochMs = event.postTime,
            fingerprint = fingerprint,
        )
        PaymentEventQueueStore(context).enqueue(queued)
        PaymentLogger.eventQueuedForReview(queued.id, "stale_notification")
    }

    /**
     * Retries a failed understanding call a couple of times before giving up.
     *
     * The single-shot version turned any transient failure into a permanently
     * lost payment, because the fingerprint had already been written to the
     * 24h dedup cache and the notification is never re-delivered. Waking from
     * an idle stretch is exactly when the first request is most likely to hit
     * a not-yet-reconnected network.
     */
    private fun understandWithRetry(event: PaymentNotificationEvent): PaymentNotificationResult {
        var last: PaymentNotificationResult = PaymentNotificationResult.Failure("no_attempt")
        for (attempt in 1..MAX_LLM_ATTEMPTS) {
            val result = client.understand(event)
            if (result is PaymentNotificationResult.Success) return result

            last = result
            val reason = (result as PaymentNotificationResult.Failure).reason
            // Missing build config can't fix itself between attempts.
            if (reason == "client_misconfigured") return result

            if (attempt < MAX_LLM_ATTEMPTS) {
                PaymentLogger.llmCallRetrying(event, attempt, reason)
                try {
                    Thread.sleep(RETRY_BACKOFF_MS * attempt)
                } catch (_: InterruptedException) {
                    Thread.currentThread().interrupt()
                    return result
                }
            }
        }
        return last
    }

    private fun buildPayload(sbn: StatusBarNotification): NotificationPayload {
        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()
        val textLines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            ?.map { it.toString() }
            ?: emptyList()
        return NotificationPayload(
            packageName = sbn.packageName,
            title = title,
            text = text,
            bigText = bigText,
            textLines = textLines,
            postTime = sbn.postTime,
            key = sbn.key,
        )
    }

    private fun buildFingerprint(payload: NotificationPayload): String {
        val key = payload.key
        if (!key.isNullOrBlank()) return key
        val minuteBucket = payload.postTime / 60_000L
        return "${payload.packageName}|${payload.combinedText.hashCode()}|$minuteBucket"
    }

    override fun onDestroy() {
        executor.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val TAG = "PaymentDetect"

        private const val MAX_LLM_ATTEMPTS = 3
        private const val RETRY_BACKOFF_MS = 1_500L
    }
}
