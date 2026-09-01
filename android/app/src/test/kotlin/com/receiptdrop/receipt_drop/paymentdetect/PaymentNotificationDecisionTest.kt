package com.receiptdrop.receipt_drop.paymentdetect

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PaymentNotificationDecisionTest {

    private fun understanding(
        type: PaymentTransactionType,
        amount: Double? = 18.50,
        confidence: Double = 0.9,
    ) = PaymentNotificationUnderstanding(
        transactionType = type,
        merchant = "Starbucks",
        counterparty = null,
        amount = amount,
        currency = "MYR",
        confidence = confidence,
    )

    @Test
    fun `payment with sufficient confidence shows overlay`() {
        assertTrue(shouldShowOverlay(understanding(PaymentTransactionType.PAYMENT)))
    }

    @Test
    fun `transfer_out with sufficient confidence shows overlay`() {
        assertTrue(shouldShowOverlay(understanding(PaymentTransactionType.TRANSFER_OUT)))
    }

    @Test
    fun `transfer_in is always suppressed`() {
        assertFalse(shouldShowOverlay(understanding(PaymentTransactionType.TRANSFER_IN)))
    }

    @Test
    fun `unknown is suppressed`() {
        assertFalse(shouldShowOverlay(understanding(PaymentTransactionType.UNKNOWN)))
    }

    @Test
    fun `null amount is suppressed`() {
        assertFalse(shouldShowOverlay(understanding(PaymentTransactionType.PAYMENT, amount = null)))
    }

    @Test
    fun `zero amount is suppressed`() {
        assertFalse(shouldShowOverlay(understanding(PaymentTransactionType.PAYMENT, amount = 0.0)))
    }

    @Test
    fun `negative amount is suppressed`() {
        assertFalse(shouldShowOverlay(understanding(PaymentTransactionType.PAYMENT, amount = -5.0)))
    }

    @Test
    fun `confidence below threshold is suppressed`() {
        assertFalse(shouldShowOverlay(understanding(PaymentTransactionType.PAYMENT, confidence = 0.2)))
    }

    @Test
    fun `confidence exactly at threshold is allowed`() {
        assertTrue(
            shouldShowOverlay(
                understanding(PaymentTransactionType.PAYMENT, confidence = CONFIDENCE_THRESHOLD),
            ),
        )
    }

    @Test
    fun `a notification delivered promptly is not stale`() {
        assertFalse(isStaleForOverlay(postTimeMs = 10_000L, nowMs = 12_000L))
    }

    @Test
    fun `a notification released after an idle stretch is stale`() {
        // The Doze case: posted, held back by the OS, delivered on the next
        // wake half an hour later.
        val postedAt = 1_000_000L
        val deliveredAt = postedAt + 30 * 60 * 1000

        assertTrue(isStaleForOverlay(postTimeMs = postedAt, nowMs = deliveredAt))
    }

    @Test
    fun `exactly at the threshold is not yet stale`() {
        assertFalse(
            isStaleForOverlay(
                postTimeMs = 0L,
                nowMs = STALE_NOTIFICATION_MS,
            ),
        )
    }

    @Test
    fun `a clock skewed backwards is never treated as stale`() {
        // A future postTime must not underflow into a huge positive age.
        assertFalse(isStaleForOverlay(postTimeMs = 20_000L, nowMs = 10_000L))
    }
}
