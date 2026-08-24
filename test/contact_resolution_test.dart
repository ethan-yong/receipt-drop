import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/logic/contact_resolution_merge.dart';
import 'package:receipt_drop/domain/models/bill_split.dart';

void main() {
  group('mergeContactResolutions', () {
    test('a matched resolution merges into the friend-id set', () {
      final merged = mergeContactResolutions(
        friendIds: const {},
        contacts: const {},
        results: const [
          MatchedContactResolution(userId: 'sarah-uuid', displayName: 'Sarah', avatarUrl: null),
        ],
      );
      expect(merged.friendIds, {'sarah-uuid'});
      expect(merged.contacts, isEmpty);
    });

    test('a matched non-friend still merges into the same friend-id set — no separate pending bucket', () {
      // The caller's already-loaded friends list doesn't contain 'john-uuid'
      // — nothing about that changes where the merge puts it.
      final merged = mergeContactResolutions(
        friendIds: const {'existing-friend'},
        contacts: const {},
        results: const [
          MatchedContactResolution(userId: 'john-uuid', displayName: 'John', avatarUrl: null),
        ],
      );
      expect(merged.friendIds, {'existing-friend', 'john-uuid'});
    });

    test('an unmatched resolution merges into the external-contacts map exactly as Phase 1', () {
      const draft = ExternalContactDraft(id: 'draft-1', name: 'Alex', phoneDigits: '60123456789');
      final merged = mergeContactResolutions(
        friendIds: const {},
        contacts: const {},
        results: const [UnmatchedContactResolution(draft)],
      );
      expect(merged.contacts, {'draft-1': draft});
      expect(merged.friendIds, isEmpty);
    });

    test('two device contacts sharing one normalized phone, both matched to the same user, produce exactly one friend-id entry', () {
      final merged = mergeContactResolutions(
        friendIds: const {},
        contacts: const {},
        results: const [
          MatchedContactResolution(userId: 'sarah-uuid', displayName: 'Sarah (mobile)', avatarUrl: null),
          MatchedContactResolution(userId: 'sarah-uuid', displayName: 'Sarah (work)', avatarUrl: null),
        ],
      );
      expect(merged.friendIds, {'sarah-uuid'});
    });

    test('a person already selected as a friend row who is also phone-matched in the same session still results in exactly one entry', () {
      final merged = mergeContactResolutions(
        friendIds: const {'sarah-uuid'}, // manually picked from the friends list
        contacts: const {},
        results: const [
          MatchedContactResolution(userId: 'sarah-uuid', displayName: 'Sarah', avatarUrl: null),
        ],
      );
      expect(merged.friendIds, {'sarah-uuid'});
      expect(merged.friendIds.length, 1);
    });

    test('duplicate unmatched phone numbers across two contacts are deduped', () {
      const first = ExternalContactDraft(id: 'draft-1', name: 'Alex A', phoneDigits: '60111111111');
      const second = ExternalContactDraft(id: 'draft-2', name: 'Alex B', phoneDigits: '60111111111');
      final merged = mergeContactResolutions(
        friendIds: const {},
        contacts: const {},
        results: const [UnmatchedContactResolution(first), UnmatchedContactResolution(second)],
      );
      expect(merged.contacts.length, 1);
      expect(merged.contacts['draft-1'], first);
    });

    test('a mix of matched and unmatched resolutions in one call routes each correctly', () {
      const externalDraft = ExternalContactDraft(id: 'draft-1', name: 'Alex', phoneDigits: '60111111111');
      final merged = mergeContactResolutions(
        friendIds: const {},
        contacts: const {},
        results: const [
          MatchedContactResolution(userId: 'sarah-uuid', displayName: 'Sarah', avatarUrl: null),
          UnmatchedContactResolution(externalDraft),
        ],
      );
      expect(merged.friendIds, {'sarah-uuid'});
      expect(merged.contacts, {'draft-1': externalDraft});
    });
  });
}
