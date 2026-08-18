package com.receiptdrop.receipt_drop.paymentdetect

/**
 * Framework-free snapshot of the fields we care about from an Android
 * [android.service.notification.StatusBarNotification]. Extracted once by
 * [PaymentNotificationListenerService] and passed down through the rest of
 * the pipeline (heuristic, client, logger) — nothing downstream of the
 * listener touches the Android notification APIs directly, which is what
 * makes every other piece here plain-JVM unit-testable.
 */
data class NotificationPayload(
    val packageName: String,
    val title: String?,
    val text: String?,
    val bigText: String?,
    val textLines: List<String>,
    val postTime: Long,
    val key: String?,
) {
    /**
     * Every distinct, non-blank text field joined into one string — the
     * input both [FinancialNotificationHeuristic] and the LLM pipeline
     * reason over. Order: text, bigText, textLines, title, deduplicated.
     */
    val combinedText: String by lazy {
        val parts = LinkedHashSet<String>()
        text?.takeIf { it.isNotBlank() }?.let { parts.add(it) }
        bigText?.takeIf { it.isNotBlank() }?.let { parts.add(it) }
        for (line in textLines) {
            if (line.isNotBlank()) parts.add(line)
        }
        title?.takeIf { it.isNotBlank() }?.let { parts.add(it) }
        parts.joinToString(" \n ")
    }
}
