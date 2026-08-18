package com.receiptdrop.receipt_drop.paymentdetect

import android.app.Notification
import android.content.Context
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log
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
    private var categoryMatcher: CategoryMatcher? = null
    private val executor: ExecutorService = Executors.newCachedThreadPool()

    override fun onCreate() {
        super.onCreate()
        dedupCache = PaymentEventDedupCache(applicationContext)
        client = PaymentNotificationClient()
        heartbeat = PaymentListenerHeartbeat(applicationContext)
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
        dedupCache.remember(fingerprint)

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
        when (val result = client.understand(event)) {
            is PaymentNotificationResult.Success -> {
                val understanding = result.understanding
                PaymentLogger.llmCallSucceeded(understanding)

                if (understanding.transactionType == PaymentTransactionType.TRANSFER_IN) {
                    // Detected, logged, deduped — but the app's transaction
                    // model is expense-only with no income concept, so this
                    // is never surfaced further (no overlay, no transaction).
                    PaymentLogger.transferInSuppressed(understanding)
                    return
                }

                if (!shouldShowOverlay(understanding)) {
                    // A real LLM response that just wasn't actionable
                    // (unknown / no amount / low confidence) — log for
                    // diagnosis and show a minimal, dismiss-only fallback
                    // card rather than staying completely silent, since the
                    // system did genuinely attempt to understand this one
                    // (unlike a pure network/timeout failure, handled below).
                    PaymentLogger.unknownOrLowConfidenceSuppressed(event, result)
                    PaymentOverlayService.showUnderstandingFailed(context, event)
                    return
                }

                val suggestedCategory = categoryMatcher
                    ?.guessWithConfidence(understanding.displayName ?: "", event.rawText)
                    ?.category

                PaymentLogger.overlayShown(understanding)
                PaymentOverlayService.show(context, event, understanding, suggestedCategory, fingerprint)
            }

            is PaymentNotificationResult.Failure -> {
                // Infrastructure failure (network/timeout/malformed response) —
                // log only, no overlay. Interrupting the user for a
                // connectivity blip is noise, not signal; a genuine LLM
                // "unknown" verdict (above) is a different, bounded case.
                PaymentLogger.unknownOrLowConfidenceSuppressed(event, result)
            }
        }
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
    }
}
