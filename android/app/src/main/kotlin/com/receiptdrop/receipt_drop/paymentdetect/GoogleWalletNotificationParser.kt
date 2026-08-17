package com.receiptdrop.receipt_drop.paymentdetect

import android.app.Notification
import android.service.notification.StatusBarNotification

/**
 * Parses Google Wallet tap-to-pay notifications.
 *
 * The package name below (`com.google.android.apps.walletnfcrel`) is the
 * commonly-cited Google Wallet/Pay package but is UNCONFIRMED for this
 * device/region — verify it via `adb logcat -s PaymentDetect` after a real
 * tap-to-pay (see [PaymentNotificationListenerService], which logs every
 * notification's package/title/text regardless of whether it's recognized)
 * and adjust [supportedPackages] / the regexes below to match what's
 * actually observed. Do not assume this is correct without checking.
 */
class GoogleWalletNotificationParser : PaymentNotificationParser {
    override val id: String = "google_wallet"

    override val supportedPackages: Set<String> = setOf(
        "com.google.android.apps.walletnfcrel",
    )

    // Malaysian Ringgit formatting: "RM12.30" / "RM 1,234.50" / "MYR12.30".
    private val amountRegex = Regex("""(?:RM|MYR)\s?([\d,]+\.\d{2})""", RegexOption.IGNORE_CASE)

    // "RM12.30 at Starbucks" / "You paid Starbucks RM12.30".
    private val merchantAtRegex = Regex(
        """(?:RM|MYR)\s?[\d,]+\.\d{2}\s+at\s+(.+)$""",
        RegexOption.IGNORE_CASE,
    )
    private val paidMerchantRegex = Regex(
        """paid\s+(.+?)\s+(?:RM|MYR)\s?[\d,]+\.\d{2}""",
        RegexOption.IGNORE_CASE,
    )

    override fun tryParse(sbn: StatusBarNotification): ParsedPayment? {
        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()

        val candidates = listOfNotNull(text, bigText, title)
        val combined = candidates.joinToString(" \n ")

        val amountMatch = amountRegex.find(combined)
        if (amountMatch == null) {
            PaymentLogger.parseFailed(sbn.packageName, "no amount match in: $combined")
            return null
        }
        val amount = amountMatch.groupValues[1].replace(",", "").toDoubleOrNull()
        if (amount == null) {
            PaymentLogger.parseFailed(sbn.packageName, "amount not numeric: ${amountMatch.value}")
            return null
        }

        val merchant = extractMerchant(combined, title)
        if (merchant.isNullOrBlank()) {
            PaymentLogger.parseFailed(sbn.packageName, "no merchant extracted from: $combined")
            return null
        }

        return ParsedPayment(
            merchantRaw = merchant.trim(),
            amountMyr = amount,
            sourcePackage = sbn.packageName,
            notificationKey = sbn.key,
            postedAtEpochMs = sbn.postTime,
            parserId = id,
        )
    }

    private fun extractMerchant(combined: String, title: String?): String? {
        merchantAtRegex.find(combined)?.let { return it.groupValues[1] }
        paidMerchantRegex.find(combined)?.let { return it.groupValues[1] }
        // Fallback: the title alone, when it isn't just a generic "Google
        // Wallet" label and doesn't itself contain the amount.
        if (!title.isNullOrBlank() && !amountRegex.containsMatchIn(title)) {
            return title
        }
        return null
    }
}
