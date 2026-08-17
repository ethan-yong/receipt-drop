package com.receiptdrop.receipt_drop.paymentdetect

import android.service.notification.StatusBarNotification

/**
 * One payment-app-specific notification parser. Implementations must not
 * guess — return null when the amount can't be confidently extracted rather
 * than emitting a wrong value. Registered in [PaymentParserRegistry], which
 * is the single extension point for supporting a new bank/wallet app.
 */
interface PaymentNotificationParser {
    val id: String

    /** Package names this parser knows how to read. */
    val supportedPackages: Set<String>

    fun tryParse(sbn: StatusBarNotification): ParsedPayment?
}
