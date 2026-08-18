package com.receiptdrop.receipt_drop.paymentdetect

/** Mirrors services/ocr-api/ocr_api/payment_notification_understanding.py's
 * response schema — see that file for the authoritative field semantics. */
enum class PaymentTransactionType {
    PAYMENT,
    TRANSFER_OUT,
    TRANSFER_IN,
    UNKNOWN;

    companion object {
        fun fromWire(value: String?): PaymentTransactionType = when (value) {
            "payment" -> PAYMENT
            "transfer_out" -> TRANSFER_OUT
            "transfer_in" -> TRANSFER_IN
            else -> UNKNOWN
        }

        /**
         * Counterpart to [fromWire] for a value that was round-tripped
         * through an Intent extra as [name]. That handoff is internal to the
         * app, so it carries the enum name ("TRANSFER_OUT") rather than the
         * server's wire spelling ("transfer_out") — passing it back through
         * [fromWire] silently yields [UNKNOWN], which shows a transfer as
         * "New payment".
         */
        fun fromName(value: String?): PaymentTransactionType =
            values().firstOrNull { it.name == value } ?: UNKNOWN
    }
}

/**
 * Normalized result of the Payment Notification LLM pipeline
 * (POST /understand-payment-notification). The server already enforces
 * "never invent" (a typed result always has a positive amount; merchant is
 * only ever set for PAYMENT, counterparty only for the transfer types) —
 * this class is just the Kotlin-side mirror of that already-validated
 * shape, not a second validation pass.
 */
data class PaymentNotificationUnderstanding(
    val transactionType: PaymentTransactionType,
    val merchant: String?,
    val counterparty: String?,
    val amount: Double?,
    val currency: String,
    val confidence: Double,
) {
    /** Whichever of merchant/counterparty applies to this transaction type,
     * for display in the overlay — never both, per the server's contract. */
    val displayName: String?
        get() = merchant ?: counterparty
}
