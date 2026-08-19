package com.receiptdrop.receipt_drop.paymentdetect

import android.content.Context

/**
 * User-facing on/off switch for the whole payment-detection feature, owned by
 * the Profile → "Payment detection" toggle (MainActivity's `payment_events`
 * channel writes it; the Flutter Settings screen reads it back).
 *
 * Persisted natively rather than only in Flutter's prefs because the listener
 * runs in a process where the Flutter engine may not be alive when a
 * notification arrives — it has to be able to honour "off" on its own. When a
 * notification is posted while this is off, [PaymentNotificationListenerService]
 * returns immediately: no LLM call, no overlay.
 *
 * Defaults to enabled so an install that already granted notification access
 * (before this toggle existed) keeps working without the user re-enabling it.
 */
class PaymentDetectionSettings(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun isEnabled(): Boolean = prefs.getBoolean(KEY_ENABLED, true)

    fun setEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    companion object {
        private const val PREFS_NAME = "payment_detection_settings"
        private const val KEY_ENABLED = "enabled"
    }
}
