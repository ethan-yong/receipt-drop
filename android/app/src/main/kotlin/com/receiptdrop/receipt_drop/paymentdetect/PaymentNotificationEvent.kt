package com.receiptdrop.receipt_drop.paymentdetect

/**
 * Generic, provider-agnostic representation of a notification that cleared
 * the local financial heuristic and is being sent to the Payment
 * Notification LLM pipeline for understanding. No bank-specific parsing
 * happens to produce this — it's just the raw text plus where it came from.
 */
data class PaymentNotificationEvent(
    val sourcePackage: String,
    val sourceProvider: String?,
    val rawText: String,
    val postTime: Long,
    val notificationKey: String?,
)
