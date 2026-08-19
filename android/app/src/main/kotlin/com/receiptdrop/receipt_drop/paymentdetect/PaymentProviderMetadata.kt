package com.receiptdrop.receipt_drop.paymentdetect

/**
 * Purely cosmetic package -> display-name lookup, used only to enrich logs
 * and the saved transaction's notes text (e.g. "Auto-detected from
 * Maybank2u" instead of a bare package name).
 *
 * HARD CONTRACT: this map must NEVER gate notification processing, NEVER
 * determine which code path runs, and NEVER influence transaction
 * classification. A package that isn't in this map goes through the exact
 * same heuristic -> LLM pipeline as one that is — [lookup] simply returns
 * null and [sourceProvider][PaymentNotificationEvent.sourceProvider] is
 * left null. Nothing else in this package reads this map.
 *
 * A package appearing here is NOT a claim that provider is "supported" —
 * real compatibility depends entirely on whether that app's actual
 * notification wording matches what the LLM can understand, which is
 * unverified until tested on a real device.
 */
object PaymentProviderMetadata {
    // Best-effort, unconfirmed guesses at common Malaysian bank/e-wallet
    // package names — see docs/system/decisions.md. Purely cosmetic; wrong
    // or missing entries have zero effect on whether detection works.
    private val DISPLAY_NAMES = mapOf(
        "com.google.android.apps.walletnfcrel" to "Google Wallet",
        "my.com.maybank2u.life" to "Maybank2u",
        "com.tng.digital" to "Touch 'n Go eWallet",
        "com.cimb.octo" to "CIMB OCTO",
        "com.cimbbank.cimbmy" to "CIMB Clicks",
        "my.com.publicbank.mypb" to "Public Bank / MyPB",
        "com.hlb.connect" to "Hong Leong Connect",
        "my.com.rhb.mobilebanking" to "RHB Mobile Banking",
        "my.com.bankislam.goapp" to "Bank Islam",
        "com.ambank.amonline" to "AmBank",
        "com.alliancebank.mobile" to "Alliance Bank",
        "com.uob.mighty" to "UOB Malaysia",
        "com.ocbc.mobilebankingmy" to "OCBC Malaysia",
        "com.scb.breezebanking.my" to "Standard Chartered Malaysia",
    )

    fun lookup(packageName: String): String? = DISPLAY_NAMES[packageName]
}
