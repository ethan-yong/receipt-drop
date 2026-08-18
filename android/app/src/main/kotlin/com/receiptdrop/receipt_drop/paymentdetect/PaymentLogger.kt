package com.receiptdrop.receipt_drop.paymentdetect

import android.util.Log
import com.receiptdrop.receipt_drop.BuildConfig

/**
 * Single logging surface for the payment-detection feature (tag
 * "PaymentDetect") — every component logs through here instead of calling
 * [Log] directly, so `adb logcat -s PaymentDetect` shows the whole flow in
 * one place during development.
 *
 * Development logging mode: [verboseLoggingEnabled] is the one flippable
 * flag gating every log line that contains notification/transaction
 * content (merchant, amounts, raw text). Defaults to [BuildConfig.DEBUG];
 * flip it to false to silence content logging in a debug build without a
 * rebuild-affecting code change, or leave it as-is and it's already off in
 * release builds. Log lines carrying sensitive (financial) content are
 * marked with a `[FINANCIAL]` prefix so it's unambiguous which log lines
 * contain real notification/transaction data.
 */
object PaymentLogger {
    private const val TAG = "PaymentDetect"

    @Volatile
    var verboseLoggingEnabled: Boolean = BuildConfig.DEBUG

    fun notificationReceived(payload: NotificationPayload) {
        if (verboseLoggingEnabled) {
            Log.d(
                TAG,
                "[FINANCIAL] notification received: pkg=${payload.packageName} " +
                    "title=${payload.title} text=${payload.text}",
            )
        } else {
            Log.d(TAG, "notification received: pkg=${payload.packageName}")
        }
    }

    fun financialHeuristicMatched(payload: NotificationPayload, matchedKeyword: String?) {
        Log.d(
            TAG,
            "financial heuristic matched: pkg=${payload.packageName} keyword=$matchedKeyword",
        )
    }

    /**
     * The specific "capture this for me" line (dev-logging requirement): a
     * notification cleared the local heuristic (looked financial enough to
     * bother the LLM) but the LLM call failed, timed out, or returned
     * unknown/no-amount.
     *
     * The *why* — a transport failure reason like `http_401`/`timeout`, or
     * the verdict shape the LLM came back with — is always logged: it names
     * no merchant, amount, or counterparty, and without it a release build
     * reports every distinct failure identically, which makes a field report
     * ("it didn't work") impossible to act on. Only the financial payload
     * (raw notification text, amount) stays behind [verboseLoggingEnabled].
     */
    fun unknownOrLowConfidenceSuppressed(
        event: PaymentNotificationEvent,
        result: PaymentNotificationResult,
    ) {
        val diagnostic = when (result) {
            is PaymentNotificationResult.Success ->
                "verdict=${result.understanding.transactionType} " +
                    "hasAmount=${result.understanding.amount != null} " +
                    "confidence=${result.understanding.confidence}"
            is PaymentNotificationResult.Failure -> "failureReason=${result.reason}"
        }
        if (verboseLoggingEnabled) {
            val financial = when (result) {
                is PaymentNotificationResult.Success ->
                    " amount=${result.understanding.amount}"
                is PaymentNotificationResult.Failure -> ""
            }
            Log.w(
                TAG,
                "[FINANCIAL] could not understand payment notification: " +
                    "pkg=${event.sourcePackage} $diagnostic " +
                    "rawText=${event.rawText}$financial",
            )
        } else {
            Log.w(
                TAG,
                "could not understand payment notification: " +
                    "pkg=${event.sourcePackage} $diagnostic",
            )
        }
    }

    fun llmCallSucceeded(understanding: PaymentNotificationUnderstanding) {
        if (verboseLoggingEnabled) {
            Log.d(
                TAG,
                "[FINANCIAL] LLM call succeeded: transactionType=${understanding.transactionType} " +
                    "displayName=${understanding.displayName} amount=${understanding.amount} " +
                    "currency=${understanding.currency} confidence=${understanding.confidence}",
            )
        } else {
            Log.d(TAG, "LLM call succeeded: transactionType=${understanding.transactionType}")
        }
    }

    fun duplicateIgnored(fingerprint: String) {
        Log.d(TAG, "duplicate ignored: fingerprint=$fingerprint")
    }

    fun transferInSuppressed(understanding: PaymentNotificationUnderstanding) {
        if (verboseLoggingEnabled) {
            Log.d(
                TAG,
                "[FINANCIAL] incoming transfer suppressed (income not supported): " +
                    "counterparty=${understanding.counterparty} amount=${understanding.amount}",
            )
        } else {
            Log.d(TAG, "incoming transfer suppressed")
        }
    }

    fun overlayShown(understanding: PaymentNotificationUnderstanding) {
        if (verboseLoggingEnabled) {
            Log.d(
                TAG,
                "[FINANCIAL] overlay shown: displayName=${understanding.displayName} " +
                    "amount=${understanding.amount}",
            )
        } else {
            Log.d(TAG, "overlay shown")
        }
    }

    fun overlayDismissed(reason: String) {
        Log.d(TAG, "overlay dismissed: reason=$reason")
    }

    fun categorySelected(category: String) {
        Log.d(TAG, "category selected: category=$category")
    }

    fun eventQueued(id: String) {
        Log.d(TAG, "event queued: id=$id")
    }
}
