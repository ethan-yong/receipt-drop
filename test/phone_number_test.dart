import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/phone_number.dart';

void main() {
  group('normalizePhoneForWhatsApp', () {
    test('local 0-prefixed number gets the default Malaysia country code', () {
      expect(normalizePhoneForWhatsApp('012-345 6789'), '60123456789');
    });

    test('explicit +60 prefix is kept, formatting stripped', () {
      expect(normalizePhoneForWhatsApp('+60 12-345 6789'), '60123456789');
    });

    test('bare 60-prefixed digits are unchanged', () {
      expect(normalizePhoneForWhatsApp('60123456789'), '60123456789');
    });

    test('a different explicit country code is preserved', () {
      expect(normalizePhoneForWhatsApp('+1 415-555-0100'), '14155550100');
    });

    test('too few digits after stripping returns null', () {
      expect(normalizePhoneForWhatsApp('12345'), null);
    });

    test('empty or non-numeric input returns null', () {
      expect(normalizePhoneForWhatsApp(''), null);
      expect(normalizePhoneForWhatsApp('   '), null);
    });

    test('is deterministic — identical input always normalizes the same way', () {
      const raw = '013-987 6543';
      expect(normalizePhoneForWhatsApp(raw), normalizePhoneForWhatsApp(raw));
    });

    test('0123456789 (bare local, no separators) normalizes with the default country code', () {
      expect(normalizePhoneForWhatsApp('0123456789'), '60123456789');
    });

    test('+60123456789 (explicit country code, no separators) drops only the plus', () {
      expect(normalizePhoneForWhatsApp('+60123456789'), '60123456789');
    });

    test('+60 12 345 6789 (explicit country code, space-separated) normalizes the same way', () {
      expect(normalizePhoneForWhatsApp('+60 12 345 6789'), '60123456789');
    });

    test('012-345-6789 (dash-separated local) normalizes the same way', () {
      expect(normalizePhoneForWhatsApp('012-345-6789'), '60123456789');
    });
  });
}
