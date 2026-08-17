package com.receiptdrop.receipt_drop.paymentdetect

/**
 * Output of a [PaymentNotificationParser] — a payment notification that was
 * successfully understood. MYR-only, matching the rest of the app (see
 * OutboxTransactions.amountMyr in lib/data/local/tables.dart).
 */
data class ParsedPayment(
    val merchantRaw: String,
    val amountMyr: Double,
    val sourcePackage: String,
    val notificationKey: String?,
    val postedAtEpochMs: Long,
    val parserId: String,
)
