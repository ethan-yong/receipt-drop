import 'package:url_launcher/url_launcher.dart';

/// Opens WhatsApp (or falls back to WhatsApp Web / the App Store if it
/// isn't installed) with [message] pre-filled in a chat to [phoneDigits]
/// (bare digits, no leading '+' — see `phone_number.dart`).
///
/// `https://wa.me/...` is WhatsApp's universal link: it always resolves at
/// the OS level, so no `canLaunchUrl` pre-check or platform query
/// declaration is needed (those only matter for a raw `whatsapp://`
/// scheme, which this deliberately avoids). Returns whether the OS
/// reports it handed off to a handler — never confirmation that the
/// recipient received anything.
Future<bool> openWhatsAppReminder({
  required String phoneDigits,
  required String message,
}) {
  final uri = Uri.parse('https://wa.me/$phoneDigits?text=${Uri.encodeComponent(message)}');
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
