/// Builds the `wa.me` deep-link URI for a WhatsApp reminder. Pure and
/// unit-testable — no platform channel involved, unlike `openWhatsAppReminder`
/// in `whatsapp_launcher_io.dart`, which wraps this with the actual
/// `url_launcher` call.
Uri buildWhatsAppReminderUri({required String phoneDigits, required String message}) {
  return Uri.parse('https://wa.me/$phoneDigits?text=${Uri.encodeComponent(message)}');
}
