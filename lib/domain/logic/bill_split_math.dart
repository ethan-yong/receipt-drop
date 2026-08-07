/// Divides [totalCents] across [personIds] as whole cents so shares always
/// sum exactly to [totalCents]: everyone gets `totalCents ~/ n`, and the
/// first `totalCents % n` ids (in list order) get one extra cent.
Map<String, int> splitCentsEvenly(int totalCents, List<String> personIds) {
  if (personIds.isEmpty) {
    throw ArgumentError.value(personIds, 'personIds', 'must not be empty');
  }
  final n = personIds.length;
  final base = totalCents ~/ n;
  final remainder = totalCents - base * n;
  final shares = <String, int>{};
  for (var i = 0; i < n; i++) {
    shares[personIds[i]] = base + (i < remainder ? 1 : 0);
  }
  return shares;
}

/// MYR convenience wrapper around [splitCentsEvenly]. Rounds [totalMyr] to
/// the nearest cent before splitting, and converts shares back to MYR.
Map<String, double> splitEqual({
  required double totalMyr,
  required List<String> personIds,
}) {
  final totalCents = (totalMyr * 100).round();
  final centShares = splitCentsEvenly(totalCents, personIds);
  return centShares.map((id, cents) => MapEntry(id, cents / 100));
}

/// One receipt line item's price plus who it's currently assigned to.
/// [assignedPersonIds] must be non-empty — the UI is responsible for never
/// allowing the last person on an item to be unassigned (mirrors the
/// source prototype's "must keep at least one person" rule); this is the
/// pure-logic backstop.
class ItemAssignmentInput {
  const ItemAssignmentInput({
    required this.lineItemId,
    required this.priceMyr,
    required this.assignedPersonIds,
  });

  final String lineItemId;
  final double priceMyr;
  final List<String> assignedPersonIds;
}

/// Sums each item's price across its assigned people, splitting each item's
/// price in whole cents (via [splitCentsEvenly]) rather than naive float
/// division, so each item's shares — and therefore the grand total — sum
/// exactly.
Map<String, double> splitByItems(List<ItemAssignmentInput> items) {
  final totalsCents = <String, int>{};
  for (final item in items) {
    final itemCents = (item.priceMyr * 100).round();
    final itemShares = splitCentsEvenly(itemCents, item.assignedPersonIds);
    itemShares.forEach((id, cents) {
      totalsCents[id] = (totalsCents[id] ?? 0) + cents;
    });
  }
  return totalsCents.map((id, cents) => MapEntry(id, cents / 100));
}
