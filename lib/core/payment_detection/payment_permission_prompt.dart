import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../widgets/receipt_sheet_widgets.dart';
import '../bootstrap/app_prefs.dart';
import '../theme/receipt_sheet_theme.dart';
import 'payment_event_bridge.dart';

/// First-run Android prompt for the two payment-detection permissions that
/// have no system runtime dialog (unlike POST_NOTIFICATIONS / location).
///
/// Android only allows these via a Settings toggle, so this shows an in-app
/// rationale then opens that toggle — the same pattern as "Allow" for
/// notifications, just one extra tap. No-ops on iOS/web. Each permission is
/// asked at most once per install; Profile still has the Settings rows.
abstract final class PaymentPermissionPrompt {
  static bool _inFlight = false;

  static Future<void> maybeShow(BuildContext context) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (_inFlight) return;
    _inFlight = true;
    try {
      final openedSettings = await _promptNotificationAccess(context);
      if (openedSettings || !context.mounted) return;
      await _promptOverlay(context);
    } finally {
      _inFlight = false;
    }
  }

  /// Returns true when the system Settings screen was opened, so the
  /// overlay prompt can wait until the next resume.
  static Future<bool> _promptNotificationAccess(BuildContext context) async {
    if (AppPrefs.paymentNotificationAccessPrompted) return false;
    if (await PaymentEventBridge.isNotificationAccessGranted()) {
      await AppPrefs.setPaymentNotificationAccessPrompted();
      return false;
    }
    if (!context.mounted) return false;

    final allow = await _showRationale(
      context,
      icon: '🔔',
      title: 'Allow notification access',
      body:
          "Receipt Drop can automatically save your spending by reading "
          "payment notifications from apps like Maybank, Touch 'n Go, and "
          "Google Wallet. Android will open the settings screen next — "
          "just turn on Receipt Drop.",
    );
    await AppPrefs.setPaymentNotificationAccessPrompted();
    if (allow == true) {
      await PaymentEventBridge.openNotificationAccessSettings();
      return true;
    }
    return false;
  }

  static Future<void> _promptOverlay(BuildContext context) async {
    if (AppPrefs.paymentOverlayPrompted) return;
    if (await PaymentEventBridge.isOverlayPermissionGranted()) {
      await AppPrefs.setPaymentOverlayPrompted();
      return;
    }
    if (!context.mounted) return;

    final allow = await _showRationale(
      context,
      icon: '🪟',
      title: 'Allow display over other apps',
      body:
          'Shows a small category picker on top of your banking app after a '
          'payment, without opening Receipt Drop. Android will open a '
          'settings screen — turn on Receipt Drop.',
    );
    await AppPrefs.setPaymentOverlayPrompted();
    if (allow == true) {
      await PaymentEventBridge.openOverlayPermissionSettings();
    }
  }

  static Future<bool?> _showRationale(
    BuildContext context, {
    required String icon,
    required String title,
    required String body,
  }) {
    return showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierColor: const Color(0x80231F1A),
      builder: (ctx) => _RationaleDialog(icon: icon, title: title, body: body),
    );
  }
}

/// The gold-badge / cream-card rationale dialog shared by both
/// [PaymentPermissionPrompt] prompts — reuses the receipt-flow sheets' gold
/// + cream + Baloo 2 mini design system ([ReceiptSheetColors], [balooText],
/// [ReceiptSheetCta], [ReceiptSheetLink]) rather than introducing a new,
/// near-duplicate palette for this one dialog.
class _RationaleDialog extends StatelessWidget {
  const _RationaleDialog({
    required this.icon,
    required this.title,
    required this.body,
  });

  final String icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: ReceiptSheetColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: ReceiptSheetColors.gold,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: ReceiptSheetColors.ctaShadow,
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(icon, style: const TextStyle(fontSize: 24)),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: balooText(
                21,
                FontWeight.w800,
                color: ReceiptSheetColors.heading,
                letterSpacing: -0.3,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              body,
              style: balooText(
                14,
                FontWeight.w500,
                color: ReceiptSheetColors.body,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 22),
            ReceiptSheetCta(
              label: 'Continue  ›',
              onPressed: () => Navigator.pop(context, true),
            ),
            ReceiptSheetLink(
              label: 'Not now',
              color: ReceiptSheetColors.sub,
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
  }
}
