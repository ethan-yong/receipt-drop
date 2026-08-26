/// Unreachable on web: the "add from phone contacts" / WhatsApp reminder
/// affordance is gated behind `PlatformUtils.isMobile` in
/// `bill_split_step_who.dart` / `bill_split_step_review.dart`, so this stub
/// only exists to satisfy the conditional export.
Future<bool> openWhatsAppReminder({
  required String phoneDigits,
  required String message,
}) {
  throw UnsupportedError('WhatsApp reminders are not supported on web.');
}

/// Always false: WhatsApp app-install probing is meaningless on web, and
/// this branch is unreachable anyway (gated behind `PlatformUtils.isMobile`
/// upstream).
Future<bool> isWhatsAppInstalled() => Future.value(false);
