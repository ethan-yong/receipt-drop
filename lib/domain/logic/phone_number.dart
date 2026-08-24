/// Normalizes a raw phone number (as read from device contacts, in any
/// local format) into bare digits suitable for a `wa.me` WhatsApp deep link
/// — E.164 digits, no leading `+`. Defaults to Malaysia's country code since
/// Receipt Drop targets Malaysian users; most saved contacts are stored in
/// local `0`-prefixed form (e.g. `012-345 6789`) rather than with a country
/// code.
///
/// Returns null if, after stripping formatting, there aren't enough digits
/// left to plausibly be a phone number.
String? normalizePhoneForWhatsApp(String raw, {String defaultCountryCode = '60'}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  final hasPlus = trimmed.startsWith('+');
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;

  String normalized;
  if (hasPlus) {
    // Explicit country code, e.g. "+60 12-345 6789" -> "60123456789".
    normalized = digits;
  } else if (digits.startsWith('0')) {
    // Local format, e.g. "012-345 6789" -> "60123456789".
    normalized = '$defaultCountryCode${digits.substring(1)}';
  } else if (digits.startsWith(defaultCountryCode)) {
    // Already has the default country code but no '+', e.g. "60123456789".
    normalized = digits;
  } else {
    // No recognizable country code or local leading zero — assume it still
    // needs the default country code prepended (e.g. bare "123456789").
    normalized = '$defaultCountryCode$digits';
  }

  // A plausible phone number (country code + subscriber number) is at least
  // 8 digits; anything shorter is more likely a typo or a non-phone value.
  if (normalized.length < 8) return null;
  return normalized;
}
