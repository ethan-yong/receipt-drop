package com.receiptdrop.receipt_drop.paymentdetect

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Durable native -> Flutter handoff for category-selected payment events.
 * The Flutter engine may not be running when a category is picked, so this
 * writes straight to SharedPreferences (as a JSON array) rather than going
 * through any Dart-side storage. [drainAll] is non-destructive; the Flutter
 * side acks by id only after it has successfully saved the transaction, so
 * a crash mid-drain never loses an event.
 */
data class QueuedPaymentEvent(
    val id: String,
    val merchantRaw: String,
    val amountMyr: Double,
    val category: String,
    val sourcePackage: String,
    val occurredAtEpochMs: Long,
    val fingerprint: String,
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "merchantRaw" to merchantRaw,
        "amountMyr" to amountMyr,
        "category" to category,
        "sourcePackage" to sourcePackage,
        "occurredAtEpochMs" to occurredAtEpochMs,
        "fingerprint" to fingerprint,
    )

    fun toJson(): JSONObject = JSONObject().apply {
        put("id", id)
        put("merchantRaw", merchantRaw)
        put("amountMyr", amountMyr)
        put("category", category)
        put("sourcePackage", sourcePackage)
        put("occurredAtEpochMs", occurredAtEpochMs)
        put("fingerprint", fingerprint)
    }

    companion object {
        fun fromJson(json: JSONObject): QueuedPaymentEvent = QueuedPaymentEvent(
            id = json.getString("id"),
            merchantRaw = json.getString("merchantRaw"),
            amountMyr = json.getDouble("amountMyr"),
            category = json.getString("category"),
            sourcePackage = json.getString("sourcePackage"),
            occurredAtEpochMs = json.getLong("occurredAtEpochMs"),
            fingerprint = json.getString("fingerprint"),
        )
    }
}

class PaymentEventQueueStore(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    @Synchronized
    fun enqueue(event: QueuedPaymentEvent) {
        val events = readAll().toMutableList()
        events.add(event)
        writeAll(events)
    }

    @Synchronized
    fun drainAll(): List<QueuedPaymentEvent> = readAll()

    @Synchronized
    fun acknowledge(ids: Set<String>) {
        if (ids.isEmpty()) return
        val remaining = readAll().filterNot { it.id in ids }
        writeAll(remaining)
    }

    private fun readAll(): List<QueuedPaymentEvent> {
        val raw = prefs.getString(KEY_QUEUE, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).mapNotNull { i ->
                try {
                    QueuedPaymentEvent.fromJson(array.getJSONObject(i))
                } catch (_: Exception) {
                    null
                }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun writeAll(events: List<QueuedPaymentEvent>) {
        val array = JSONArray()
        for (event in events) array.put(event.toJson())
        prefs.edit().putString(KEY_QUEUE, array.toString()).apply()
    }

    companion object {
        private const val PREFS_NAME = "payment_event_queue"
        private const val KEY_QUEUE = "queue"
    }
}
