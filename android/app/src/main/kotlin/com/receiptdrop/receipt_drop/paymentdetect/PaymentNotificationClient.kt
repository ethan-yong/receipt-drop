package com.receiptdrop.receipt_drop.paymentdetect

import com.receiptdrop.receipt_drop.BuildConfig
import org.json.JSONObject
import java.io.IOException
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL

/** Outcome of a call to the Payment Notification LLM pipeline. Never
 * throws — every failure mode (timeout, network error, non-2xx, malformed
 * response) is a [Failure] the caller can log and gracefully skip. */
sealed class PaymentNotificationResult {
    data class Success(val understanding: PaymentNotificationUnderstanding) :
        PaymentNotificationResult()

    data class Failure(val reason: String) : PaymentNotificationResult()
}

/** Minimal seam for testing [PaymentNotificationClient] without real
 * network I/O. The default implementation is [HttpUrlConnector]. A `fun
 * interface` so tests can pass a plain lambda via SAM conversion. */
fun interface PaymentNotificationConnector {
    /** Returns (statusCode, responseBody). Throws [IOException] (including
     * [SocketTimeoutException]) on any transport-level failure. */
    fun post(url: String, headers: Map<String, String>, body: String, timeoutMs: Int): Pair<Int, String>
}

object HttpUrlConnector : PaymentNotificationConnector {
    override fun post(url: String, headers: Map<String, String>, body: String, timeoutMs: Int): Pair<Int, String> {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "POST"
            connection.doOutput = true
            connection.connectTimeout = timeoutMs
            connection.readTimeout = timeoutMs
            for ((key, value) in headers) connection.setRequestProperty(key, value)
            OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { it.write(body) }

            val statusCode = connection.responseCode
            val stream = if (statusCode in 200..299) connection.inputStream else connection.errorStream
            val responseBody = stream?.bufferedReader(Charsets.UTF_8)?.use { it.readText() } ?: ""
            return statusCode to responseBody
        } finally {
            connection.disconnect()
        }
    }
}

/**
 * Native caller for the Payment Notification LLM pipeline
 * (payment-notification-proxy -> services/ocr-api's
 * POST /understand-payment-notification). Deliberately blocking — the
 * listener is responsible for calling [understand] off the binder thread
 * (see PaymentNotificationListenerService), not this class.
 *
 * Auth: only the build-time shared secret (X-Payment-Notification-Secret) —
 * never a Supabase service-role key, user JWT, or database credential.
 * Request body is deliberately minimal: exactly notification_text,
 * source_package, posted_at — no other notification metadata is ever sent.
 */
class PaymentNotificationClient(
    private val endpointUrl: String =
        "${BuildConfig.SUPABASE_URL.trimEnd('/')}/functions/v1/payment-notification-proxy",
    private val secret: String = BuildConfig.PAYMENT_NOTIFICATION_PROXY_SECRET,
    private val anonKey: String = BuildConfig.SUPABASE_ANON_KEY,
    private val timeoutMs: Int = DEFAULT_TIMEOUT_MS,
    private val connector: PaymentNotificationConnector = HttpUrlConnector,
) {
    fun understand(event: PaymentNotificationEvent): PaymentNotificationResult {
        if (endpointUrl.startsWith("/") || secret.isBlank()) {
            // SUPABASE_URL/PAYMENT_NOTIFICATION_PROXY_SECRET not configured
            // in local.properties yet — fail closed, don't attempt a request
            // to a malformed URL.
            return PaymentNotificationResult.Failure("client_misconfigured")
        }

        val requestBody = JSONObject().apply {
            put("notification_text", event.rawText)
            put("source_package", event.sourcePackage)
            put("posted_at", event.postTime)
        }.toString()

        val headers = mapOf(
            "Content-Type" to "application/json",
            "X-Payment-Notification-Secret" to secret,
            "apikey" to anonKey,
        )

        val (statusCode, responseBody) = try {
            connector.post(endpointUrl, headers, requestBody, timeoutMs)
        } catch (_: SocketTimeoutException) {
            return PaymentNotificationResult.Failure("timeout")
        } catch (e: IOException) {
            return PaymentNotificationResult.Failure("network_error: ${e.message}")
        }

        if (statusCode !in 200..299) {
            return PaymentNotificationResult.Failure("http_$statusCode: ${responseBody.take(300)}")
        }

        val understanding = parseResponse(responseBody)
            ?: return PaymentNotificationResult.Failure("malformed_response: ${responseBody.take(300)}")
        return PaymentNotificationResult.Success(understanding)
    }

    private fun optNullableString(json: JSONObject, key: String): String? {
        if (!json.has(key) || json.isNull(key)) return null
        return json.optString(key).takeUnless { it.isBlank() }
    }

    private fun parseResponse(body: String): PaymentNotificationUnderstanding? {
        return try {
            val json = JSONObject(body)
            PaymentNotificationUnderstanding(
                transactionType = PaymentTransactionType.fromWire(optNullableString(json, "transaction_type")),
                merchant = optNullableString(json, "merchant"),
                counterparty = optNullableString(json, "counterparty"),
                amount = if (json.isNull("amount") || !json.has("amount")) null else json.optDouble("amount").takeUnless { it.isNaN() },
                currency = json.optString("currency", "MYR").ifBlank { "MYR" },
                confidence = json.optDouble("confidence", 0.0).takeUnless { it.isNaN() } ?: 0.0,
            )
        } catch (_: Exception) {
            null
        }
    }

    companion object {
        // Comfortably above the server's own PAYMENT_NOTIFICATION_LLM_TIMEOUT_SECONDS
        // (8s) plus network/proxy overhead, while still keeping the overlay's
        // appearance feeling reasonably prompt.
        private const val DEFAULT_TIMEOUT_MS = 12_000
    }
}
