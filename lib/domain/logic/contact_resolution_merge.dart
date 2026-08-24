import '../models/bill_split.dart';

/// The result of merging [ContactResolution]s into an in-progress Bill
/// Split selection.
class ContactSelectionState {
  const ContactSelectionState({required this.friendIds, required this.contacts});

  final Set<String> friendIds;
  final Map<String, ExternalContactDraft> contacts;
}

/// Pure merge step for [ContactPickerSheet] results into a
/// [BillSplitSheet]'s in-progress selection. A [MatchedContactResolution]
/// (the number matched an existing Receipt Drop account, friend or not)
/// always lands in [friendIds] — reusing the same set manually-picked
/// friends go into is exactly why a person picked both ways (a friend row
/// checked directly, and separately phone-matched via a device contact)
/// collapses to one entry: `Set.add` on an already-present id is a no-op.
/// An [UnmatchedContactResolution] lands in [contacts], deduped by
/// normalized phone.
ContactSelectionState mergeContactResolutions({
  required Set<String> friendIds,
  required Map<String, ExternalContactDraft> contacts,
  required List<ContactResolution> results,
}) {
  final mergedFriendIds = {...friendIds};
  final mergedContacts = {...contacts};
  final existingPhones = mergedContacts.values.map((c) => c.phoneDigits).toSet();
  for (final result in results) {
    switch (result) {
      case MatchedContactResolution(:final userId):
        mergedFriendIds.add(userId);
      case UnmatchedContactResolution(:final draft):
        if (existingPhones.contains(draft.phoneDigits)) continue;
        mergedContacts[draft.id] = draft;
        existingPhones.add(draft.phoneDigits);
    }
  }
  return ContactSelectionState(friendIds: mergedFriendIds, contacts: mergedContacts);
}
