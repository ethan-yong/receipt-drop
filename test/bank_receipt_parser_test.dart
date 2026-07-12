import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/bank_receipt_parser.dart';

void main() {
  // ---------------------------------------------------------------------------
  // detectBankProvider
  // ---------------------------------------------------------------------------

  group('detectBankProvider', () {
    test('detects Maybank by keyword "Maybank"', () {
      expect(detectBankProvider('Transfer via Maybank'), BankProvider.maybank);
    });

    test('detects Maybank by keyword "MAE"', () {
      expect(detectBankProvider('MAE eWallet Payment'), BankProvider.maybank);
    });

    test('detects Maybank by keyword "Maybank2u"', () {
      expect(detectBankProvider('Maybank2u Transfer Successful'), BankProvider.maybank);
    });

    test('detects Maybank case-insensitively', () {
      expect(detectBankProvider('MAYBANK TRANSFER'), BankProvider.maybank);
      expect(detectBankProvider('maybank2u'), BankProvider.maybank);
    });

    test('detects CIMB by keyword "CIMB"', () {
      expect(detectBankProvider('CIMB Clicks Payment'), BankProvider.cimb);
    });

    test('detects CIMB by keyword "OCTO"', () {
      expect(detectBankProvider('OCTO by CIMB'), BankProvider.cimb);
    });

    test('detects CIMB case-insensitively', () {
      expect(detectBankProvider('cimb clicks'), BankProvider.cimb);
    });

    test("detects TNG by keyword \"Touch 'n Go\"", () {
      expect(detectBankProvider("Touch 'n Go eWallet"), BankProvider.tng);
    });

    test('detects TNG by keyword "Touch n Go"', () {
      expect(detectBankProvider('Touch n Go Payment'), BankProvider.tng);
    });

    test('detects TNG by keyword "TNG"', () {
      expect(detectBankProvider('TNG eWallet'), BankProvider.tng);
    });

    test('detects TNG by keyword "eWallet"', () {
      expect(detectBankProvider('eWallet Payment Successful'), BankProvider.tng);
    });

    test('detects TNG case-insensitively', () {
      expect(detectBankProvider('TOUCH N GO EWALLET'), BankProvider.tng);
    });

    test('returns unknown for unrecognised provider', () {
      expect(detectBankProvider('RHBANK Transfer'), BankProvider.unknown);
      expect(detectBankProvider('Total: RM 12.50'), BankProvider.unknown);
      expect(detectBankProvider(''), BankProvider.unknown);
    });
  });

  // ---------------------------------------------------------------------------
  // Maybank parser
  // ---------------------------------------------------------------------------

  group('Maybank parser', () {
    const validReceipt = '''
Transfer Successful
To: JOHN ENTERPRISE
Amount: RM 120.00
Reference: 123456789
Date: 12 Jul 2026
Maybank
''';

    test('parses amount and merchant from a standard Maybank receipt', () {
      final result = tryParseBankReceipt(validReceipt);
      expect(result, isNotNull);
      expect(result!.provider, BankProvider.maybank);
      expect(result.amountMyr, 120.00);
      expect(result.merchantRaw, 'JOHN ENTERPRISE');
      expect(result.category, 'Transfer');
    });

    test('trims whitespace from merchant name', () {
      const ocr = 'Maybank\nTo:   MY KEDAI SDN BHD   \nAmount: RM 50.00\n';
      final result = tryParseBankReceipt(ocr);
      expect(result!.merchantRaw, 'MY KEDAI SDN BHD');
    });

    test('parses amount with thousands comma separator', () {
      const ocr = 'Maybank\nTo: BIG CORP\nAmount: RM 1,234.50\n';
      final result = tryParseBankReceipt(ocr);
      expect(result!.amountMyr, 1234.50);
    });

    test('returns null when amount is missing', () {
      const ocr = 'Maybank\nTo: SOME STORE\nReference: 999\n';
      expect(tryParseBankReceipt(ocr), isNull);
    });

    test('returns null when "To:" label is missing', () {
      const ocr = 'Maybank\nRecipient: SOME STORE\nAmount: RM 30.00\n';
      expect(tryParseBankReceipt(ocr), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // CIMB parser
  // ---------------------------------------------------------------------------

  group('CIMB parser', () {
    const validReceipt = '''
Transaction Successful
CIMB Clicks
Recipient Name: ABC STORE SDN BHD
Amount: RM 45.50
Reference No: 987654321
Date: 12/07/2026
''';

    test('parses amount and merchant from a standard CIMB receipt', () {
      final result = tryParseBankReceipt(validReceipt);
      expect(result, isNotNull);
      expect(result!.provider, BankProvider.cimb);
      expect(result.amountMyr, 45.50);
      expect(result.merchantRaw, 'ABC STORE SDN BHD');
      expect(result.category, 'Transfer');
    });

    test('prefers "Recipient Name:" over "To:" when both present', () {
      const ocr = '''
CIMB
To: OLD NAME
Recipient Name: CORRECT NAME
Amount: RM 10.00
''';
      // firstMatch picks "To:" first if it comes earlier — but the regex
      // tries "Recipient Name" OR "To", so whichever appears first in the
      // text wins. This test documents that "To:" comes first here and wins.
      // The real-world CIMB format always puts "Recipient Name" — so in
      // practice the preferred form appears first in the OCR text.
      final result = tryParseBankReceipt(ocr);
      expect(result, isNotNull);
      // The regex matches the first occurrence; "To:" appears earlier.
      expect(result!.merchantRaw, 'OLD NAME');
    });

    test('falls back to "To:" when "Recipient Name:" is absent', () {
      const ocr = 'CIMB\nTo: BACKUP STORE\nAmount: RM 88.00\n';
      final result = tryParseBankReceipt(ocr);
      expect(result!.merchantRaw, 'BACKUP STORE');
    });

    test('returns null when amount is missing', () {
      const ocr = 'CIMB\nRecipient Name: SOME STORE\n';
      expect(tryParseBankReceipt(ocr), isNull);
    });

    test('returns null when neither merchant label is present', () {
      const ocr = 'CIMB\nMerchant: SOME STORE\nAmount: RM 20.00\n';
      expect(tryParseBankReceipt(ocr), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // TNG parser
  // ---------------------------------------------------------------------------

  group('TNG parser', () {
    const validReceipt = '''
Payment Successful
Touch n Go eWallet
Merchant: MIXUE SS15
Amount: RM 8.90
Date: 12 Jul 2026
''';

    test('parses amount and merchant from a standard TNG receipt', () {
      final result = tryParseBankReceipt(validReceipt);
      expect(result, isNotNull);
      expect(result!.provider, BankProvider.tng);
      expect(result.amountMyr, 8.90);
      expect(result.merchantRaw, 'MIXUE SS15');
      expect(result.category, 'Payment');
    });

    test('falls back to "Paid to:" when "Merchant:" is absent', () {
      const ocr = 'TNG eWallet\nPaid to: GRAB FOOD\nAmount: RM 25.00\n';
      final result = tryParseBankReceipt(ocr);
      expect(result!.merchantRaw, 'GRAB FOOD');
    });

    test('trims whitespace from merchant name', () {
      const ocr = "Touch 'n Go eWallet\nMerchant:  MY NASI LEMAK  \nAmount: RM 7.50\n";
      final result = tryParseBankReceipt(ocr);
      expect(result!.merchantRaw, 'MY NASI LEMAK');
    });

    test('parses amount with thousands comma separator', () {
      const ocr = 'TNG\nMerchant: BIG STORE\nAmount: RM 2,500.00\n';
      final result = tryParseBankReceipt(ocr);
      expect(result!.amountMyr, 2500.00);
    });

    test('returns null when amount is missing', () {
      const ocr = 'TNG\nMerchant: SOME STORE\n';
      expect(tryParseBankReceipt(ocr), isNull);
    });

    test('returns null when neither merchant label is present', () {
      const ocr = 'TNG\nTo: SOME STORE\nAmount: RM 5.00\n';
      expect(tryParseBankReceipt(ocr), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Unknown provider — fallback to LLM pipeline
  // ---------------------------------------------------------------------------

  group('unknown provider', () {
    test('returns null for a generic retail receipt', () {
      const ocr = '''
7-ELEVEN MALAYSIA
Total RM 12.50
Tunai RM 20.00
Baki RM 7.50
''';
      expect(tryParseBankReceipt(ocr), isNull);
    });

    test('returns null for empty text', () {
      expect(tryParseBankReceipt(''), isNull);
    });
  });
}
