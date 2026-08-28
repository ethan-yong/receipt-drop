package com.receiptdrop.receipt_drop.paymentdetect

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The queue is the durable handoff from the native listener to Flutter and it
 * survives app updates, so its serialization has to tolerate rows written by
 * an older build as well as the newer uncategorized shape.
 */
class QueuedPaymentEventTest {

    private fun event(
        category: String? = "Food & Drink",
        suggestedCategory: String? = null,
    ) = QueuedPaymentEvent(
        id = "id-1",
        merchantRaw = "KOPITIAM SS15",
        amountMyr = 12.30,
        category = category,
        suggestedCategory = suggestedCategory,
        sourcePackage = "com.maybank2u.life",
        occurredAtEpochMs = 1_700_000_000_000L,
        fingerprint = "fp-1",
    )

    @Test
    fun `round-trips a categorized event`() {
        val restored = QueuedPaymentEvent.fromJson(event().toJson())

        assertEquals(event(), restored)
    }

    @Test
    fun `round-trips an uncategorized event with a suggestion`() {
        val original = event(category = null, suggestedCategory = "Transport")

        val restored = QueuedPaymentEvent.fromJson(original.toJson())

        assertEquals(original, restored)
        assertNull(restored.category)
        assertEquals("Transport", restored.suggestedCategory)
    }

    @Test
    fun `parses a row written before suggestedCategory existed`() {
        // Exactly what the previous build wrote: a required category and no
        // suggestion key at all. Dropping these on update would silently lose
        // payments the user had already categorized.
        val legacy = JSONObject(
            """
            {"id":"id-1","merchantRaw":"KOPITIAM SS15","amountMyr":12.30,
             "category":"Food & Drink","sourcePackage":"com.maybank2u.life",
             "occurredAtEpochMs":1700000000000,"fingerprint":"fp-1"}
            """.trimIndent(),
        )

        val restored = QueuedPaymentEvent.fromJson(legacy)

        assertEquals("Food & Drink", restored.category)
        assertNull(restored.suggestedCategory)
    }

    @Test
    fun `carries the payment time rather than the drain time`() {
        // The event can sit in the queue for hours; Flutter files the
        // transaction under this timestamp, not when it happened to drain.
        val restored = QueuedPaymentEvent.fromJson(event().toJson())

        assertEquals(1_700_000_000_000L, restored.occurredAtEpochMs)
    }

    @Test
    fun `exposes an uncategorized event over the method channel as a null category`() {
        val map = event(category = null, suggestedCategory = "Groceries").toMap()

        assertNull(map["category"])
        assertEquals("Groceries", map["suggestedCategory"])
    }
}
