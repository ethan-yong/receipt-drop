package com.receiptdrop.receipt_drop.paymentdetect

/**
 * The ONLY job of this object: "does this notification look sufficiently
 * financial to bother calling the Payment Notification LLM?" — a coarse,
 * intentionally loose cost/latency prefilter, not a correctness gate. It
 * has no bank-specific logic and no package allowlist; the LLM (with its
 * "never invent, return unknown when ambiguous" contract) is the actual
 * precision gate that decides whether a real transaction gets created.
 * False positives here just mean one extra LLM call — false positives in a
 * *created transaction* are prevented downstream, not here.
 *
 * Conservative by design: requires BOTH a currency+amount pattern AND at
 * least one strong transaction keyword, so an ordinary notification that
 * merely contains "RM" or a number doesn't trip this.
 */
object FinancialNotificationHeuristic {
    private val AMOUNT_REGEX =
        Regex("""(?:RM|MYR)\s?[\d,]+(?:\.\d{1,2})?""", RegexOption.IGNORE_CASE)

    private val STRONG_KEYWORDS = listOf(
        "paid", "payment", "purchase", "spent", "debit", "credit",
        "transfer", "transferred", "received", "sent", "duitnow",
        "successful", "deducted", "withdrawn",
    )

    fun looksFinancial(payload: NotificationPayload): Boolean {
        val text = payload.combinedText
        if (!AMOUNT_REGEX.containsMatchIn(text)) return false
        val lower = text.lowercase()
        return STRONG_KEYWORDS.any { lower.contains(it) }
    }

    /** First matching keyword, for log detail — null if none matched
     * (e.g. when only the amount pattern failed, [looksFinancial] is
     * already false and this wouldn't be called). */
    fun matchedKeyword(payload: NotificationPayload): String? {
        val lower = payload.combinedText.lowercase()
        return STRONG_KEYWORDS.firstOrNull { lower.contains(it) }
    }
}
