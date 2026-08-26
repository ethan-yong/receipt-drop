import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/core/bootstrap/app_prefs.dart';
import 'package:receipt_drop/core/payment_detection/payment_permission_prompt.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('PaymentPermissionPrompt.shouldAutoPrompt', () {
    test('returns false when not Android', () {
      expect(
        PaymentPermissionPrompt.shouldAutoPrompt(
          isAndroid: false,
          promptAlreadyDone: false,
          paymentDetectionEnabled: true,
          notificationAccessGranted: false,
          overlayPermissionGranted: false,
        ),
        isFalse,
      );
    });

    test('returns false when prompt already done', () {
      expect(
        PaymentPermissionPrompt.shouldAutoPrompt(
          isAndroid: true,
          promptAlreadyDone: true,
          paymentDetectionEnabled: true,
          notificationAccessGranted: false,
          overlayPermissionGranted: false,
        ),
        isFalse,
      );
    });

    test('returns false when payment detection is off', () {
      expect(
        PaymentPermissionPrompt.shouldAutoPrompt(
          isAndroid: true,
          promptAlreadyDone: false,
          paymentDetectionEnabled: false,
          notificationAccessGranted: false,
          overlayPermissionGranted: false,
        ),
        isFalse,
      );
    });

    test('returns false when both permissions already granted', () {
      expect(
        PaymentPermissionPrompt.shouldAutoPrompt(
          isAndroid: true,
          promptAlreadyDone: false,
          paymentDetectionEnabled: true,
          notificationAccessGranted: true,
          overlayPermissionGranted: true,
        ),
        isFalse,
      );
    });

    test('returns true when notification access is missing', () {
      expect(
        PaymentPermissionPrompt.shouldAutoPrompt(
          isAndroid: true,
          promptAlreadyDone: false,
          paymentDetectionEnabled: true,
          notificationAccessGranted: false,
          overlayPermissionGranted: true,
        ),
        isTrue,
      );
    });

    test('returns true when overlay permission is missing', () {
      expect(
        PaymentPermissionPrompt.shouldAutoPrompt(
          isAndroid: true,
          promptAlreadyDone: false,
          paymentDetectionEnabled: true,
          notificationAccessGranted: true,
          overlayPermissionGranted: false,
        ),
        isTrue,
      );
    });

    test('returns true when both permissions are missing', () {
      expect(
        PaymentPermissionPrompt.shouldAutoPrompt(
          isAndroid: true,
          promptAlreadyDone: false,
          paymentDetectionEnabled: true,
          notificationAccessGranted: false,
          overlayPermissionGranted: false,
        ),
        isTrue,
      );
    });
  });

  group('AppPrefs.paymentPermissionPromptDone', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppPrefs.init();
      await AppPrefs.clearForTest();
    });

    test('defaults to false', () {
      expect(AppPrefs.paymentPermissionPromptDone, isFalse);
    });

    test('setPaymentPermissionPromptDone persists true', () async {
      await AppPrefs.setPaymentPermissionPromptDone();
      expect(AppPrefs.paymentPermissionPromptDone, isTrue);
    });

    test('clearLocalCache removes the flag', () async {
      await AppPrefs.setPaymentPermissionPromptDone();
      await AppPrefs.clearLocalCache();
      expect(AppPrefs.paymentPermissionPromptDone, isFalse);
    });
  });
}
