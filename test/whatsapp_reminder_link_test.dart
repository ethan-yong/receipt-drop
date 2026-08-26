import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/bill_split_reminder_message.dart';
import 'package:receipt_drop/domain/logic/whatsapp_reminder_link.dart';

void main() {
  group('buildWhatsAppReminderUri', () {
    test('uses the wa.me universal link with the phone digits in the path', () {
      final uri = buildWhatsAppReminderUri(phoneDigits: '60123456789', message: 'hi');
      expect(uri.scheme, 'https');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/60123456789');
    });

    test('phone digits never appear with +, spaces, dashes, or parens', () {
      final uri = buildWhatsAppReminderUri(phoneDigits: '60123456789', message: 'hi');
      final full = uri.toString();
      for (final banned in ['+', ' ', '-', '(', ')']) {
        expect(full.contains('60123456789$banned'), false);
      }
      expect(uri.path.contains('+'), false);
    });

    test('unicode characters round-trip through the encoded query param', () {
      const message = 'Reminder for café bill — thanks!';
      final uri = buildWhatsAppReminderUri(phoneDigits: '60123456789', message: message);
      expect(uri.queryParameters['text'], message);
    });

    test('ampersand is escaped in the raw URL but round-trips correctly', () {
      const message = 'Fish & Chips — RM 12.50';
      final uri = buildWhatsAppReminderUri(phoneDigits: '60123456789', message: message);
      expect(uri.toString().contains('Fish & Chips'), false);
      expect(uri.queryParameters['text'], message);
    });

    test('apostrophe round-trips correctly', () {
      const message = "Sarah's share from McDonald's";
      final uri = buildWhatsAppReminderUri(phoneDigits: '60123456789', message: message);
      expect(uri.queryParameters['text'], message);
    });

    test('em-dash round-trips correctly', () {
      const message = 'Chicken Burger — RM18.00';
      final uri = buildWhatsAppReminderUri(phoneDigits: '60123456789', message: message);
      expect(uri.queryParameters['text'], message);
    });

    test('embedded newlines round-trip correctly', () {
      const message = 'Line one\nLine two\n\nLine four';
      final uri = buildWhatsAppReminderUri(phoneDigits: '60123456789', message: message);
      expect(uri.queryParameters['text'], message);
    });

    test('RM amounts with spaces round-trip correctly', () {
      const message = 'Total: RM 12.50';
      final uri = buildWhatsAppReminderUri(phoneDigits: '60123456789', message: message);
      expect(uri.queryParameters['text'], message);
    });

    test('a full deterministic reminder message round-trips end to end', () {
      final message = buildWhatsAppReminderMessage(
        recipientName: "Sarah",
        merchantOrPlace: "McDonald's",
        receiptDate: DateTime(2026, 8, 24),
        assignedItems: const [
          (label: 'Chicken Burger', priceMyr: 18.00),
          (label: 'Fries', priceMyr: 7.00),
        ],
        totalOwedMyr: 25.00,
      );
      final uri = buildWhatsAppReminderUri(phoneDigits: '60123456789', message: message);
      expect(uri.queryParameters['text'], message);
    });
  });
}
