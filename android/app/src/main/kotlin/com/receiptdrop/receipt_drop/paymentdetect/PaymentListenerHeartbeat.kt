package com.receiptdrop.receipt_drop.paymentdetect

import android.content.Context
import android.os.Process

/**
 * Records whether [PaymentNotificationListenerService] is actually *bound*,
 * as opposed to merely *permitted*.
 *
 * These are not the same thing, and conflating them hides a whole class of
 * silent failure. Notification access can read "allowed" in system Settings
 * while the OS never binds the service at all — most notably on MIUI/HyperOS,
 * where AutoStartManagerService rejects the bind unless the app also has
 * Background autostart enabled ("MIUILOG- Reject service"). ColorOS, Funtouch
 * and EMUI have equivalent gates. In that state the app receives zero
 * notifications forever, while every in-app check says the permission is
 * granted, so the feature looks broken with nothing to point at.
 *
 * The listener writes here on connect/disconnect; the UI reads it to tell
 * "granted and working" apart from "granted but never started".
 *
 * The stored pid is what makes a stale `connected` flag detectable: the
 * listener and the Activity share a process, so a flag left behind by an
 * earlier process (killed by the OEM memory manager, then relaunched by the
 * user without the listener being rebound) has a pid that no longer matches
 * and is correctly reported as not connected.
 */
class PaymentListenerHeartbeat(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun recordConnected() {
        prefs.edit()
            .putBoolean(KEY_CONNECTED, true)
            .putInt(KEY_CONNECTED_PID, Process.myPid())
            .putLong(KEY_LAST_CONNECTED_AT, System.currentTimeMillis())
            .apply()
    }

    fun recordDisconnected() {
        prefs.edit()
            .putBoolean(KEY_CONNECTED, false)
            .putLong(KEY_LAST_DISCONNECTED_AT, System.currentTimeMillis())
            .apply()
    }

    /**
     * Throttled: notifications arrive in bursts and this is only used to show
     * "last saw a notification N ago", so a write per notification would be
     * pointless disk churn on the binder thread.
     */
    fun recordNotificationSeen() {
        val now = System.currentTimeMillis()
        val last = prefs.getLong(KEY_LAST_NOTIFICATION_AT, 0L)
        if (now - last < NOTIFICATION_WRITE_THROTTLE_MS) return
        prefs.edit().putLong(KEY_LAST_NOTIFICATION_AT, now).apply()
    }

    /** True only when the listener connected *in the current process*. */
    fun isConnected(): Boolean {
        if (!prefs.getBoolean(KEY_CONNECTED, false)) return false
        return prefs.getInt(KEY_CONNECTED_PID, -1) == Process.myPid()
    }

    fun lastConnectedAt(): Long = prefs.getLong(KEY_LAST_CONNECTED_AT, 0L)

    fun lastNotificationAt(): Long = prefs.getLong(KEY_LAST_NOTIFICATION_AT, 0L)

    /** True when the listener has never once connected on this install. */
    fun hasNeverConnected(): Boolean = lastConnectedAt() == 0L

    companion object {
        private const val PREFS_NAME = "payment_listener_heartbeat"
        private const val KEY_CONNECTED = "connected"
        private const val KEY_CONNECTED_PID = "connected_pid"
        private const val KEY_LAST_CONNECTED_AT = "last_connected_at"
        private const val KEY_LAST_DISCONNECTED_AT = "last_disconnected_at"
        private const val KEY_LAST_NOTIFICATION_AT = "last_notification_at"
        private const val NOTIFICATION_WRITE_THROTTLE_MS = 60_000L
    }
}
