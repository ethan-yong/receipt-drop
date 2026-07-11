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
  });

  final String? merchantName;
  final List<String> merchantSearchQueries;
  final String? addressText;
  final List<String> locationClues;
  final String? vendorCategory;
  final List<String> googlePlaceTypes;
  final List<ReceiptUnderstandingLineItem> lineItems;
  final ReceiptUnderstandingConfidence confidence;

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

    return ReceiptUnderstanding(
      merchantName: asStringOrNull(json['merchant_name']),
      merchantSearchQueries: asStringList(json['merchant_search_queries']),
      addressText: asStringOrNull(json['address_text']),
      locationClues: asStringList(json['location_clues']),
      vendorCategory: asStringOrNull(json['vendor_category']),
      googlePlaceTypes: asStringList(json['google_place_types']),
      lineItems: lineItems,
      confidence: ReceiptUnderstandingConfidence.fromJson(json['confidence']),
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
