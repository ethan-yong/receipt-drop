package com.receiptdrop.receipt_drop.paymentdetect

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class CategoryMatcherTest {

    // Fixture mirrors the shape of assets/config/categories-v1.json — not
    // the full real file, just enough rule variety to exercise the tiering.
    private val fixtureJson = """
        {
          "version": "test",
          "default_category": "Others",
          "rules": [
            { "category": "Food & Drink", "any_of": ["starbucks", "mcdonald"] },
            { "category": "Groceries", "any_of": ["tesco", "aeon"] }
          ]
        }
    """.trimIndent()

    private fun matcher(): CategoryMatcher {
        val m = CategoryMatcher.fromJson(fixtureJson)
        assertNotNull(m)
        return m!!
    }

    @Test
    fun `merchant keyword hit scores 0-85`() {
        val guess = matcher().guessWithConfidence("Starbucks KLCC", "")
        assertEquals("Food & Drink", guess.category)
        assertEquals(0.85, guess.confidence, 0.0001)
    }

    @Test
    fun `body keyword hit scores 0-55 when merchant does not match`() {
        val guess = matcher().guessWithConfidence("Unknown Payee", "Reload at TESCO Kepong")
        assertEquals("Groceries", guess.category)
        assertEquals(0.55, guess.confidence, 0.0001)
    }

    @Test
    fun `no match falls back to default category at 0-10`() {
        val guess = matcher().guessWithConfidence("John Tan", "DuitNow transfer")
        assertEquals("Others", guess.category)
        assertEquals(0.10, guess.confidence, 0.0001)
    }

    @Test
    fun `matching is case-insensitive`() {
        val guess = matcher().guessWithConfidence("STARBUCKS", "")
        assertEquals("Food & Drink", guess.category)
    }

    @Test
    fun `only scans first N body lines`() {
        val manyBlankLines = (1..20).joinToString("\n") { "line $it" }
        val guess = matcher().guessWithConfidence("Unknown", "$manyBlankLines\ntesco")
        assertEquals("Others", guess.category)
    }

    @Test
    fun `malformed json returns null`() {
        assertEquals(null, CategoryMatcher.fromJson("not json"))
    }
}
