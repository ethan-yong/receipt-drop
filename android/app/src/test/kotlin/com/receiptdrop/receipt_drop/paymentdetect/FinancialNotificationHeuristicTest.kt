package com.receiptdrop.receipt_drop.paymentdetect

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FinancialNotificationHeuristicTest {

    private fun payload(text: String, title: String? = null): NotificationPayload =
        NotificationPayload(
            packageName = "com.example.bank",
            title = title,
            text = text,
            bigText = null,
            textLines = emptyList(),
            postTime = 0L,
            key = null,
        )

    @Test
    fun `amount plus strong keyword is financial`() {
        assertTrue(FinancialNotificationHeuristic.looksFinancial(payload("RM18.50 paid to Starbucks")))
    }

    @Test
    fun `received-money wording is financial`() {
        assertTrue(
            FinancialNotificationHeuristic.looksFinancial(
                payload("You have received RM50.00 from John via DuitNow"),
            ),
        )
    }

    @Test
    fun `no amount at all is not financial even with a keyword`() {
        assertFalse(FinancialNotificationHeuristic.looksFinancial(payload("Your payment method needs updating")))
    }

    @Test
    fun `amount without any strong keyword is not financial`() {
        assertFalse(FinancialNotificationHeuristic.looksFinancial(payload("RM18.50 cashback earned this month!")))
    }

    @Test
    fun `ordinary non-financial notification is ignored`() {
        assertFalse(FinancialNotificationHeuristic.looksFinancial(payload("Your Grab ride has arrived")))
    }

    @Test
    fun `amount without decimals still matches`() {
        assertTrue(FinancialNotificationHeuristic.looksFinancial(payload("RM100 transferred to John")))
    }

    @Test
    fun `matchedKeyword returns the keyword that tripped it`() {
        assertEquals("paid", FinancialNotificationHeuristic.matchedKeyword(payload("RM18.50 paid to Starbucks")))
    }
}
