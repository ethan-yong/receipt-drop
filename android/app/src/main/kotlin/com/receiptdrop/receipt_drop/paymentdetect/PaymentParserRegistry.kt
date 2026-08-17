package com.receiptdrop.receipt_drop.paymentdetect

import android.service.notification.StatusBarNotification

/**
 * Dispatches an incoming notification to the parser(s) registered for its
 * package. Adding support for a new bank/wallet app is: implement
 * [PaymentNotificationParser], add one line to [parsers] below.
 */
object PaymentParserRegistry {
    private val parsers: List<PaymentNotificationParser> = listOf(
        GoogleWalletNotificationParser(),
        // future: MaybankNotificationParser(), TouchNGoNotificationParser(), ...
    )

    private val packageIndex: Map<String, List<PaymentNotificationParser>> by lazy {
        val map = mutableMapOf<String, MutableList<PaymentNotificationParser>>()
        for (parser in parsers) {
            for (pkg in parser.supportedPackages) {
                map.getOrPut(pkg) { mutableListOf() }.add(parser)
            }
        }
        map
    }

    fun isKnownPaymentPackage(pkg: String): Boolean = packageIndex.containsKey(pkg)

    fun tryParse(sbn: StatusBarNotification): ParsedPayment? {
        val candidates = packageIndex[sbn.packageName] ?: return null
        for (parser in candidates) {
            val result = parser.tryParse(sbn)
            if (result != null) return result
        }
        return null
    }
}
