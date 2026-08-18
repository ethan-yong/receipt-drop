package com.receiptdrop.receipt_drop.paymentdetect

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException
import java.net.SocketTimeoutException

class PaymentNotificationClientTest {

    private val event = PaymentNotificationEvent(
        sourcePackage = "com.example.bank",
        sourceProvider = null,
        rawText = "RM18.50 paid to Starbucks",
        postTime = 1_000L,
        notificationKey = null,
    )

    private fun client(connector: PaymentNotificationConnector): PaymentNotificationClient =
        PaymentNotificationClient(
            endpointUrl = "https://example.supabase.co/functions/v1/payment-notification-proxy",
            secret = "test-secret",
            anonKey = "test-anon-key",
            timeoutMs = 5_000,
            connector = connector,
        )

    @Test
    fun `success maps a valid response`() {
        val body = """
            {"transaction_type":"payment","merchant":"Starbucks","amount":18.5,"currency":"MYR","confidence":0.95}
        """.trimIndent()
        val result = client { _, _, _, _ -> 200 to body }.understand(event)

        assertTrue(result is PaymentNotificationResult.Success)
        val understanding = (result as PaymentNotificationResult.Success).understanding
        assertEquals(PaymentTransactionType.PAYMENT, understanding.transactionType)
        assertEquals("Starbucks", understanding.merchant)
        assertEquals(18.5, understanding.amount!!, 0.0001)
    }

    @Test
    fun `sends only the minimal fields`() {
        var capturedBody: String? = null
        client { _, _, body, _ ->
            capturedBody = body
            200 to """{"transaction_type":"unknown"}"""
        }.understand(event)

        val body = capturedBody!!
        assertTrue(body.contains("\"notification_text\""))
        assertTrue(body.contains("\"source_package\""))
        assertTrue(body.contains("\"posted_at\""))
        // Nothing beyond the three documented fields.
        assertEquals(3, body.count { it == ':' })
    }

    @Test
    fun `sends the shared secret header not a supabase auth header`() {
        var capturedHeaders: Map<String, String>? = null
        client { _, headers, _, _ ->
            capturedHeaders = headers
            200 to """{"transaction_type":"unknown"}"""
        }.understand(event)

        assertEquals("test-secret", capturedHeaders!!["X-Payment-Notification-Secret"])
        assertTrue(!capturedHeaders!!.containsKey("Authorization"))
    }

    @Test
    fun `timeout maps to a Failure`() {
        val result = client { _, _, _, _ -> throw SocketTimeoutException("timed out") }.understand(event)
        assertTrue(result is PaymentNotificationResult.Failure)
        assertEquals("timeout", (result as PaymentNotificationResult.Failure).reason)
    }

    @Test
    fun `network error maps to a Failure`() {
        val result = client { _, _, _, _ -> throw IOException("connection reset") }.understand(event)
        assertTrue(result is PaymentNotificationResult.Failure)
    }

    @Test
    fun `non-2xx status maps to a Failure`() {
        val result = client { _, _, _, _ -> 401 to """{"error":"unauthorized"}""" }.understand(event)
        assertTrue(result is PaymentNotificationResult.Failure)
        assertTrue((result as PaymentNotificationResult.Failure).reason.startsWith("http_401"))
    }

    @Test
    fun `malformed json body maps to a Failure`() {
        val result = client { _, _, _, _ -> 200 to "not json at all" }.understand(event)
        assertTrue(result is PaymentNotificationResult.Failure)
    }

    @Test
    fun `blank secret fails closed without a network call`() {
        var called = false
        val result = PaymentNotificationClient(
            endpointUrl = "https://example.supabase.co/functions/v1/payment-notification-proxy",
            secret = "",
            anonKey = "test-anon-key",
            connector = { _, _, _, _ -> called = true; 200 to "{}" },
        ).understand(event)

        assertTrue(result is PaymentNotificationResult.Failure)
        assertEquals(false, called)
    }
}
