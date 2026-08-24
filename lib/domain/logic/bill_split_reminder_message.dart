import 'package:intl/intl.dart';

/// One line-item's label and the recipient's *share* of its price (already
/// divided across whoever else it's assigned to — see the call site in
/// `bill_split_step_review.dart`, which uses `splitByItems`/
/// `splitCentsEvenly` from `bill_split_math.dart` to compute this, exactly
/// like every other per-item amount in this feature).
typedef ReminderLineItem = ({String label, double priceMyr});

/// Builds the deterministic WhatsApp reminder message for one participant.
/// Pure: no `DateTime.now()`, no randomness, no I/O — identical inputs
/// always produce an identical string, per the "no LLM, deterministic"
/// requirement. [assignedItems] is empty for an equal-mode split (there's
/// no item breakdown to show, only the flat share).
String buildWhatsAppReminderMessage({
  required String recipientName,
  required String merchantOrPlace,
  required DateTime receiptDate,
  required List<ReminderLineItem> assignedItems,
  required double totalOwedMyr,
}) {
  final dateStr = DateFormat('d MMM').format(receiptDate);
  final buffer = StringBuffer()
    ..writeln('Hi $recipientName!')
    ..writeln('Just a reminder for your share from $merchantOrPlace on $dateStr.')
    ..writeln();

  if (assignedItems.isEmpty) {
    buffer.writeln('Your share: RM ${totalOwedMyr.toStringAsFixed(2)}');
  } else {
    for (final item in assignedItems) {
      buffer.writeln('${item.label} — RM ${item.priceMyr.toStringAsFixed(2)}');
    }
    buffer
      ..writeln()
      ..writeln('Total: RM ${totalOwedMyr.toStringAsFixed(2)}');
  }

  buffer
    ..writeln()
    ..write('Sent via Receipt Drop');

  return buffer.toString().trim();
}
