package com.receiptdrop.receipt_drop.paymentdetect

/** Single tunable place for the minimum LLM confidence required to show
 * the overlay for an otherwise-valid typed result. */
const val CONFIDENCE_THRESHOLD: Double = 0.5

/**
 * How far behind the payment a notification can be delivered and still
 * justify interrupting the user with a floating card.
 *
 * Android does not deliver notification-listener callbacks while the device
 * is dozing or the process is suspended — it releases them in a burst on the
 * next wake, which can be an hour later.
 */
const val STALE_NOTIFICATION_MS: Long = 2L * 60 * 1000

/**
 * Whether a notification arrived too late for a floating card to make sense.
 *
 * A card that appears long after the payment lands on top of whatever
 * unrelated app the user has since opened, and asks them to categorize
 * something they have moved on from — it reads as the app glitching rather
 * than helping. Past this age the payment is routed to the in-app review
 * queue instead, which loses nothing and interrupts no one.
 *
 * Pure and top-level for the same reason as [shouldShowOverlay]: testable
 * without an Android service harness.
 */
fun isStaleForOverlay(
    postTimeMs: Long,
    nowMs: Long,
    staleAfterMs: Long = STALE_NOTIFICATION_MS,
): Boolean = nowMs - postTimeMs > staleAfterMs

/**
 * The one decision point between "the LLM understood this" and "the user
 * sees a category-picker popup for it" — extracted as a pure, top-level
 * function (no Android dependencies) specifically so it's unit-testable
 * without an Android service harness, per the requirement to test
 * TRANSFER_IN suppression and unknown/low-confidence suppression directly.
 *
 * `false` (no overlay, no transaction) for any of:
 *  - transactionType == TRANSFER_IN (the app's transaction model is
 *    expense-only; incoming transfers are detected/logged/deduped but
 *    never surfaced — see PaymentNotificationListenerService)
 *  - transactionType == UNKNOWN
 *  - amount == null or amount <= 0 (invalid/non-positive)
 *  - confidence < [CONFIDENCE_THRESHOLD]
 *
 * `true` only for PAYMENT/TRANSFER_OUT with a positive amount and
 * sufficient confidence. This is a belt-and-suspenders repeat of a rule
 * already enforced server-side (parse_payment_notification_understanding
 * downgrades a typed-but-amountless result to unknown before it ever
 * leaves the server) — not the only enforcement point.
 */
fun shouldShowOverlay(
    understanding: PaymentNotificationUnderstanding,
    confidenceThreshold: Double = CONFIDENCE_THRESHOLD,
): Boolean {
    if (understanding.transactionType == PaymentTransactionType.TRANSFER_IN) return false
    if (understanding.transactionType == PaymentTransactionType.UNKNOWN) return false
    val amount = understanding.amount ?: return false
    if (amount <= 0) return false
    if (understanding.confidence < confidenceThreshold) return false
    return true
}
