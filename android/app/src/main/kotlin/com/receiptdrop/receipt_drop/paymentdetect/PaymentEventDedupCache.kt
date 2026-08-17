package com.receiptdrop.receipt_drop.paymentdetect

import android.content.Context

/**
 * Fingerprint-based dedup so the same payment doesn't spawn multiple
 * overlays/transactions when a notification is re-posted or re-delivered
 * after a service restart. Backed by SharedPreferences (survives process
 * death), with a TTL so the set doesn't grow unbounded.
 */
class PaymentEventDedupCache(context: Context) {
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun isDuplicate(fingerprint: String): Boolean {
        evictExpired()
        val entries = prefs.getStringSet(KEY_ENTRIES, emptySet()) ?: emptySet()
        val now = System.currentTimeMillis()
        return entries.any { entry ->
            val (fp, expiresAt) = splitEntry(entry) ?: return@any false
            fp == fingerprint && expiresAt > now
        }
    }

    fun remember(fingerprint: String) {
        evictExpired()
        val entries = (prefs.getStringSet(KEY_ENTRIES, emptySet()) ?: emptySet()).toMutableSet()
        val expiresAt = System.currentTimeMillis() + TTL_MS
        entries.add("$fingerprint$SEPARATOR$expiresAt")
        prefs.edit().putStringSet(KEY_ENTRIES, entries).apply()
    }

    private fun evictExpired() {
        val entries = prefs.getStringSet(KEY_ENTRIES, emptySet()) ?: emptySet()
        val now = System.currentTimeMillis()
        val kept = entries.filter { entry ->
            val (_, expiresAt) = splitEntry(entry) ?: return@filter false
            expiresAt > now
        }.toSet()
        if (kept.size != entries.size) {
            prefs.edit().putStringSet(KEY_ENTRIES, kept).apply()
        }
    }

    private fun splitEntry(entry: String): Pair<String, Long>? {
        val idx = entry.lastIndexOf(SEPARATOR)
        if (idx < 0) return null
        val expiresAt = entry.substring(idx + SEPARATOR.length).toLongOrNull() ?: return null
        return entry.substring(0, idx) to expiresAt
    }

    companion object {
        private const val PREFS_NAME = "payment_dedup_cache"
        private const val KEY_ENTRIES = "entries"

        // Separates the fingerprint from its TTL timestamp within one stored
        // entry. Fingerprints are either a notification key or our own
        // "pkg|merchant|amount|minuteBucket" string (single pipes), so a
        // double-colon delimiter can't collide with either.
        private const val SEPARATOR = "::"
        private const val TTL_MS = 24L * 60 * 60 * 1000
    }
}
