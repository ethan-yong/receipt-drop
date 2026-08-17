package com.receiptdrop.receipt_drop.paymentdetect

import android.util.Log
import com.receiptdrop.receipt_drop.BuildConfig

/**
 * Single logging surface for the payment-detection feature (tag
 * "PaymentDetect") — every component logs through here instead of calling
 * [Log] directly, so `adb logcat -s PaymentDetect` shows the whole flow in
 * one place during development. Anything containing merchant/amount text is
 * gated to debug builds.
 */
object PaymentLogger {
    private const val TAG = "PaymentDetect"

    fun notificationReceived(pkg: String, title: String?, text: String?) {
        if (BuildConfig.DEBUG) {
            Log.d(TAG, "notification received: pkg=$pkg title=$title text=$text")
        } else {
            Log.d(TAG, "notification received: pkg=$pkg")
        }
    }

    fun recognizedPaymentApp(pkg: String) {
        Log.d(TAG, "recognized as payment app: pkg=$pkg")
    }

    fun parsed(result: ParsedPayment) {
        if (BuildConfig.DEBUG) {
            Log.d(
                TAG,
                "parsed payment: parser=${result.parserId} merchant=${result.merchantRaw} " +
                    "amountMyr=${result.amountMyr} pkg=${result.sourcePackage}",
            )
        } else {
            Log.d(TAG, "parsed payment via ${result.parserId}")
        }
    }

    fun parseFailed(pkg: String, reason: String) {
        Log.d(TAG, "parse failed: pkg=$pkg reason=$reason")
    }

    fun duplicateIgnored(fingerprint: String) {
        Log.d(TAG, "duplicate ignored: fingerprint=$fingerprint")
    }

    fun overlayShown(payment: ParsedPayment) {
        Log.d(TAG, "overlay shown: merchant=${payment.merchantRaw} amountMyr=${payment.amountMyr}")
    }

    fun overlayDismissed(reason: String) {
        Log.d(TAG, "overlay dismissed: reason=$reason")
    }

    fun categorySelected(category: String, payment: ParsedPayment) {
        Log.d(TAG, "category selected: category=$category merchant=${payment.merchantRaw}")
    }

    fun eventQueued(id: String) {
        Log.d(TAG, "event queued: id=$id")
    }
}
