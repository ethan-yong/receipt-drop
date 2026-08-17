package com.receiptdrop.receipt_drop.paymentdetect

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Log

/**
 * Detection layer: receives every notification posted on the device, logs
 * it (see requirement to inspect real payloads during development), filters
 * to known payment-app packages via [PaymentParserRegistry], and on a
 * successful, non-duplicate parse triggers [PaymentOverlayService]. Does not
 * touch Drift/Supabase or any Flutter business logic — purely detect, parse,
 * dedup, hand off to the overlay.
 */
class PaymentNotificationListenerService : NotificationListenerService() {
    private lateinit var dedupCache: PaymentEventDedupCache

    override fun onCreate() {
        super.onCreate()
        dedupCache = PaymentEventDedupCache(applicationContext)
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.d(TAG, "listener connected (notification access granted)")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.d(TAG, "listener disconnected")
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val pkg = sbn.packageName
        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        PaymentLogger.notificationReceived(pkg, title, text)

        if (!PaymentParserRegistry.isKnownPaymentPackage(pkg)) return
        PaymentLogger.recognizedPaymentApp(pkg)

        val parsed = PaymentParserRegistry.tryParse(sbn)
        if (parsed == null) {
            PaymentLogger.parseFailed(pkg, "no parser matched")
            return
        }
        PaymentLogger.parsed(parsed)

        val fingerprint = buildFingerprint(parsed)
        if (dedupCache.isDuplicate(fingerprint)) {
            PaymentLogger.duplicateIgnored(fingerprint)
            return
        }
        dedupCache.remember(fingerprint)

        PaymentOverlayService.show(applicationContext, parsed, fingerprint)
    }

    private fun buildFingerprint(payment: ParsedPayment): String {
        val key = payment.notificationKey
        if (!key.isNullOrBlank()) return key
        val minuteBucket = payment.postedAtEpochMs / 60_000L
        return "${payment.sourcePackage}|${payment.merchantRaw}|${payment.amountMyr}|$minuteBucket"
    }

    companion object {
        private const val TAG = "PaymentDetect"
    }
}
