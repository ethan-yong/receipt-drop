import 'package:url_launcher/url_launcher.dart';

import '../../domain/logic/whatsapp_reminder_link.dart';

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
  final uri = buildWhatsAppReminderUri(phoneDigits: phoneDigits, message: message);
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Probes whether the WhatsApp app itself is installed, via its
/// `whatsapp://` scheme — distinct from [openWhatsAppReminder]'s universal
/// `https://wa.me` link, which always resolves regardless of install state.
/// Used to decide between opening WhatsApp directly and falling back to the
/// OS share sheet. Requires the `com.whatsapp` package-visibility `<queries>`
/// entry (Android) / `LSApplicationQueriesSchemes` entry (iOS) — without
/// those, this always returns false regardless of install state.
Future<bool> isWhatsAppInstalled() => canLaunchUrl(Uri.parse('whatsapp://send'));
