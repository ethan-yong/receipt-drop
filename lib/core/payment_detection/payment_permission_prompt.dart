import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../widgets/receipt_sheet_widgets.dart';
import '../theme/receipt_sheet_theme.dart';
import 'payment_event_bridge.dart';

/// User-initiated setup walkthrough for the two payment-detection permissions
/// that have no system runtime dialog (unlike POST_NOTIFICATIONS / location).
///
/// Android only allows these via a Settings toggle, so this shows an in-app
/// rationale then opens that toggle — the same pattern as "Allow" for
/// notifications, just one extra tap. No-ops on iOS/web.
///
/// This is only ever triggered by the user explicitly turning on the Profile →
/// "Payment detection" toggle — there is no automatic/lifecycle prompting. It
/// walks the permissions in order (notification access, the overlay that
/// renders the category picker, then the Doze exemption that decides whether
/// detection is prompt or hours late), prompting for whichever is still
/// missing. Opening a system Settings screen ends the walk for that tap; the
/// Settings rows (with their warning state) cover any step the user didn't
/// complete in one pass.
abstract final class PaymentPermissionPrompt {
  static bool _inFlight = false;

  /// Runs the permission walkthrough. Call after enabling payment detection.
  static Future<void> runSetupWalkthrough(BuildContext context) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (_inFlight) return;
    _inFlight = true;
    try {
      if (await _promptNotificationAccess(context)) return;
      if (!context.mounted) return;
      if (await _promptOverlay(context)) return;
      if (!context.mounted) return;
      await _promptBatteryOptimization(context);
    } finally {
      _inFlight = false;
    }
  }

  /// Returns true when a system Settings screen was opened, so the overlay
  /// step waits (the user has left the app to grant notification access).
  static Future<bool> _promptNotificationAccess(BuildContext context) async {
    if (await PaymentEventBridge.isNotificationAccessGranted()) return false;
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
    if (allow == true) {
      await PaymentEventBridge.openNotificationAccessSettings();
      return true;
    }
    return false;
  }

  static Future<bool> _promptOverlay(BuildContext context) async {
    if (await PaymentEventBridge.isOverlayPermissionGranted()) return false;
    if (!context.mounted) return false;

    final allow = await _showRationale(
      context,
      icon: '🪟',
      title: 'Allow display over other apps',
      body:
          'Shows a small category picker on top of your banking app after a '
          'payment, without opening Receipt Drop. Android will open a '
          'settings screen — turn on Receipt Drop.',
    );
    if (allow == true) {
      await PaymentEventBridge.openOverlayPermissionSettings();
      return true;
    }
    return false;
  }

  /// The step that decides whether detection feels instant or broken. While
  /// the phone is dozing Android simply doesn't deliver notifications to
  /// listeners, so without this a payment is picked up whenever the device
  /// next wakes — which the user experiences as the picker appearing at a
  /// random time, or only after they open the app.
  static Future<void> _promptBatteryOptimization(BuildContext context) async {
    if (await PaymentEventBridge.isBatteryOptimizationIgnored()) return;
    if (!context.mounted) return;

    final allow = await _showRationale(
      context,
      icon: '⚡',
      title: 'Allow unrestricted battery use',
      body:
          'Android pauses background apps to save power, which can delay a '
          'payment from being noticed until your phone next wakes up. '
          'Allowing unrestricted use lets Receipt Drop catch payments as they '
          'happen.',
    );
    if (allow == true) {
      await PaymentEventBridge.requestIgnoreBatteryOptimizations();
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
