package com.receiptdrop.receipt_drop.paymentdetect

import android.content.Context
import org.json.JSONObject

/**
 * Minimal Kotlin port of `CategoryConfig.guessWithConfidence` in
 * lib/domain/logic/category_matcher.dart (read in full before porting —
 * it's ~80 lines of pure case-insensitive substring matching, no async, no
 * LLM, nothing large enough to warrant anything but a direct port). Reads
 * the SAME bundled `assets/config/categories-v1.json` Flutter packages into
 * the APK (via `flutter_assets/`) — there is exactly one category taxonomy;
 * this is just a second, native reader of it, the same "documented port of
 * one algorithm across languages" precedent this codebase already uses for
 * parse_receipt_understanding/parseReceiptUnderstanding.
 *
 * Tiers, identical to the Dart original: 0.85 (a rule keyword found in
 * [merchantText]), 0.55 (a rule keyword found in [bodyText]'s first 15
 * lines), 0.10 (default category, no match).
 */
class CategoryMatcher private constructor(
    private val defaultCategory: String,
    private val rules: List<Pair<String, List<String>>>,
) {
    data class Guess(val category: String, val confidence: Double)

    fun guessWithConfidence(merchantText: String, bodyText: String, scanLines: Int = 15): Guess {
        val merchantHaystack = merchantText.lowercase()
        for ((category, keywords) in rules) {
            if (keywords.any { merchantHaystack.contains(it.lowercase()) }) {
                return Guess(category, 0.85)
            }
        }

        val lines = bodyText.split(Regex("""\r?\n""")).take(scanLines)
        for (line in lines) {
            val lineHaystack = line.lowercase()
            for ((category, keywords) in rules) {
                if (keywords.any { lineHaystack.contains(it.lowercase()) }) {
                    return Guess(category, 0.55)
                }
            }
        }

        return Guess(defaultCategory, 0.10)
    }

    companion object {
        private const val ASSET_PATH = "flutter_assets/assets/config/categories-v1.json"

        /** Returns null if the bundled asset can't be read/parsed — callers
         * treat that as "no category suggestion available" rather than
         * crashing (this must never block showing the overlay). */
        fun loadFromAssets(context: Context): CategoryMatcher? {
            return try {
                val json = context.assets.open(ASSET_PATH).bufferedReader(Charsets.UTF_8).use { it.readText() }
                fromJson(json)
            } catch (_: Exception) {
                null
            }
        }

        /** The actual parsing logic, split out from [loadFromAssets] so it's
         * testable in a pure JVM unit test (no Android Context needed). */
        fun fromJson(json: String): CategoryMatcher? {
            return try {
                val obj = JSONObject(json)
                val defaultCategory = obj.optString("default_category", "Others")
                val rulesJson = obj.optJSONArray("rules") ?: return CategoryMatcher(defaultCategory, emptyList())
                val rules = mutableListOf<Pair<String, List<String>>>()
                for (i in 0 until rulesJson.length()) {
                    val rule = rulesJson.getJSONObject(i)
                    val category = rule.getString("category")
                    val anyOf = rule.getJSONArray("any_of")
                    val keywords = (0 until anyOf.length()).map { anyOf.getString(it) }
                    rules.add(category to keywords)
                }
                CategoryMatcher(defaultCategory, rules)
            } catch (_: Exception) {
                null
            }
        }
    }
}
