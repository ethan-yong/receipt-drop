import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/models/receipt_line_item.dart';
import 'package:receipt_drop/features/share/receipt_ingest_draft.dart';
import 'package:receipt_drop/features/share/receipt_summary_view_model.dart';

ReceiptIngestDraft _draft({
  String? merchantRaw,
  double? amountMyr = 64.80,
  List<ReceiptLineItem> lineItems = const [],
}) {
  return ReceiptIngestDraft(
    localFilePath: '/tmp/receipt.jpg',
    mimeType: 'image/jpeg',
    amountMyr: amountMyr,
    needsAmount: amountMyr == null,
    merchantRaw: merchantRaw,
    categoryGuess: 'Food & Drink',
    lineItems: lineItems,
  );
}

void main() {
  test('title-cases the merchant and strips business suffixes', () {
    final vm = ReceiptSummaryViewModel.from(
      _draft(merchantRaw: 'RESTORAN ANWAR MAU'),
    );
    expect(vm.merchantDisplay, 'Restoran Anwar Mau');

    final suffixed = ReceiptSummaryViewModel.from(
      _draft(merchantRaw: 'ROCK CAFE SDN BHD'),
    );
    expect(suffixed.merchantDisplay, 'Rock Cafe');
  });

  test('carries line items through with display formatting', () {
    final vm = ReceiptSummaryViewModel.from(
      _draft(
        lineItems: const [
          ReceiptLineItem(name: 'Rsb Biasa', priceMyr: 7.0, quantity: 1),
          ReceiptLineItem(name: 'Teh O Limau Ais', priceMyr: 8.7, quantity: 3),
          ReceiptLineItem(name: 'Ayam Goreng', priceMyr: 6.0),
        ],
      ),
    );
    expect(vm.lineItemCount, 3);
    // Quantity 1 adds no information; only multi-quantity rows get a prefix.
    expect(vm.lineItems[0].displayLabel, 'Rsb Biasa');
    expect(vm.lineItems[1].displayLabel, '3× Teh O Limau Ais');
    expect(vm.lineItems[2].displayLabel, 'Ayam Goreng');
    expect(vm.lineItems[1].priceDisplay, 'RM 8.70');
  });

  test('falls back to Unknown merchant and dash amount', () {
    final vm = ReceiptSummaryViewModel.from(
      _draft(merchantRaw: null, amountMyr: null),
    );
    expect(vm.merchantDisplay, 'Unknown merchant');
    expect(vm.amountDisplay, '–');
    expect(vm.hasAmount, isFalse);
  });
}
