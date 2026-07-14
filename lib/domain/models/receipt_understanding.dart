/// LLM receipt-understanding step's structured output, produced
/// synchronously alongside OCR by `services/ocr-api`'s `POST /ocr` (see
/// `app/receipt_understanding.py`) — a cleaned merchant name, Places search
/// context, vendor category, and reconstructed line items. Field names and
/// JSON keys deliberately mirror the Python/TS ports (see
/// `supabase/functions/_shared/receipt_understanding.ts`'s "two ports of one
/// algorithm" note) so the same wire shape round-trips to
/// `transactions.llm_understanding` unchanged.
class ReceiptUnderstanding {
  const ReceiptUnderstanding({
    required this.merchantName,
    required this.merchantSearchQueries,
    required this.addressText,
    required this.locationClues,
    required this.vendorCategory,
    required this.googlePlaceTypes,
    required this.lineItems,
    required this.confidence,
    this.receiptType,
    this.transactionDate,
    this.amount,
    this.paymentMethod,
    this.transactionId,
    this.bookingReference,
    this.origin,
    this.destination,
  });

  final String? merchantName;
  final List<String> merchantSearchQueries;
  final String? addressText;
  final List<String> locationClues;
  final String? vendorCategory;
  final List<String> googlePlaceTypes;
  final List<ReceiptUnderstandingLineItem> lineItems;
  final ReceiptUnderstandingConfidence confidence;

  /// Receipt type determined by the keyword orchestrator before the LLM call.
  /// One of: restaurant, cafe, payment, grocery, retail, transport, travel, unknown.
  final String? receiptType;

  /// Skill-specific optional fields — non-null only for the relevant skill.
  final String? transactionDate;

  /// LLM-extracted payment/fare amount (payment and transport skills only).
  /// Distinct from the heuristic-parsed `amountMyr` in [ReceiptParseResult].
  final double? amount;
  final String? paymentMethod;
  final String? transactionId;
  final String? bookingReference;
  final String? origin;
  final String? destination;

  /// Defensive parse: any wrong-shaped field is dropped rather than
  /// throwing — this is a hint from an external call, never the source of
  /// truth for whether the surrounding /ocr response is usable. Returns
  /// `null` only when [json] isn't even a map.
  static ReceiptUnderstanding? tryFromJson(Object? json) {
    if (json is! Map) return null;

    String? asStringOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;
    List<String> asStringList(Object? v) => v is List
        ? [for (final e in v) if (e is String && e.isNotEmpty) e]
        : const [];

    final lineItemsJson = json['line_items'];
    final lineItems = lineItemsJson is List
        ? [
            for (final item in lineItemsJson)
              ReceiptUnderstandingLineItem.tryFromJson(item),
          ].whereType<ReceiptUnderstandingLineItem>().toList()
        : <ReceiptUnderstandingLineItem>[];

    final amountRaw = json['amount'];

    return ReceiptUnderstanding(
      merchantName: asStringOrNull(json['merchant_name']),
      merchantSearchQueries: asStringList(json['merchant_search_queries']),
      addressText: asStringOrNull(json['address_text']),
      locationClues: asStringList(json['location_clues']),
      vendorCategory: asStringOrNull(json['vendor_category']),
      googlePlaceTypes: asStringList(json['google_place_types']),
      lineItems: lineItems,
      confidence: ReceiptUnderstandingConfidence.fromJson(json['confidence']),
      receiptType: asStringOrNull(json['receipt_type']),
      transactionDate: asStringOrNull(json['transaction_date']),
      amount: amountRaw is num ? amountRaw.toDouble() : null,
      paymentMethod: asStringOrNull(json['payment_method']),
      transactionId: asStringOrNull(json['transaction_id']),
      bookingReference: asStringOrNull(json['booking_reference']),
      origin: asStringOrNull(json['origin']),
      destination: asStringOrNull(json['destination']),
    );
  }

  Map<String, dynamic> toJson() => {
        'merchant_name': merchantName,
        'merchant_search_queries': merchantSearchQueries,
        'address_text': addressText,
        'location_clues': locationClues,
        'vendor_category': vendorCategory,
        'google_place_types': googlePlaceTypes,
        'line_items': lineItems.map((it) => it.toJson()).toList(),
        'confidence': confidence.toJson(),
        if (receiptType != null) 'receipt_type': receiptType,
        if (transactionDate != null) 'transaction_date': transactionDate,
        if (amount != null) 'amount': amount,
        if (paymentMethod != null) 'payment_method': paymentMethod,
        if (transactionId != null) 'transaction_id': transactionId,
        if (bookingReference != null) 'booking_reference': bookingReference,
        if (origin != null) 'origin': origin,
        if (destination != null) 'destination': destination,
      };
}

/// One purchased item reconstructed by the LLM from noisy OCR text —
/// mirrors ocr-api's `ReceiptLineItemUnderstanding`. [price] is the row's
/// line total in MYR (never a unit price); `null` when illegible.
class ReceiptUnderstandingLineItem {
  const ReceiptUnderstandingLineItem({
    required this.name,
    required this.price,
    required this.quantity,
  });

  final String name;
  final double? price;
  final double? quantity;

  static ReceiptUnderstandingLineItem? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    if (name is! String || name.isEmpty) return null;
    final price = json['price'];
    final quantity = json['quantity'];
    return ReceiptUnderstandingLineItem(
      name: name,
      price: price is num ? price.toDouble() : null,
      quantity: quantity is num ? quantity.toDouble() : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'price': price,
        'quantity': quantity,
      };
}

/// Per-field LLM self-reported confidence (0-1), already clamped by
/// ocr-api/enrich-transaction before this ever reaches the client.
class ReceiptUnderstandingConfidence {
  const ReceiptUnderstandingConfidence({
    required this.merchant,
    required this.address,
    required this.category,
    required this.lineItems,
  });

  final double merchant;
  final double address;
  final double category;
  final double lineItems;

  static ReceiptUnderstandingConfidence fromJson(Object? json) {
    double asDouble(Object? v) => v is num ? v.toDouble() : 0.0;
    if (json is! Map) {
      return const ReceiptUnderstandingConfidence(
        merchant: 0,
        address: 0,
        category: 0,
        lineItems: 0,
      );
    }
    return ReceiptUnderstandingConfidence(
      merchant: asDouble(json['merchant']),
      address: asDouble(json['address']),
      category: asDouble(json['category']),
      lineItems: asDouble(json['line_items']),
    );
  }

  Map<String, dynamic> toJson() => {
        'merchant': merchant,
        'address': address,
        'category': category,
        'line_items': lineItems,
      };
}
