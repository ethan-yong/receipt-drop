import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/domain/models/bill_split.dart';

void main() {
  group('BillSplitParticipant', () {
    test('a friend participant is not an external contact and keys by friendUserId', () {
      const p = BillSplitParticipant(
        id: 'row-1',
        friendUserId: 'friend-uuid',
        shareMyr: 10,
        paid: false,
        paidAt: null,
        lastRemindedAt: null,
      );
      expect(p.isExternalContact, false);
      expect(p.personKey, 'friend-uuid');
    });

    test('an external contact keys by its own row id, not a friendUserId', () {
      const p = BillSplitParticipant(
        id: 'contact-row-1',
        friendUserId: null,
        contactName: 'John',
        contactPhone: '60123456789',
        shareMyr: 10,
        paid: false,
        paidAt: null,
        lastRemindedAt: null,
      );
      expect(p.isExternalContact, true);
      expect(p.personKey, 'contact-row-1');
    });
  });

  group('BillSplitView.assigneeIdsForLineItem — 5-person mixed fixture', () {
    // You (owner) + Sarah/Alex/Mike (Receipt Drop friends) + John (a pure
    // phone contact, no account) — mirrors the spec's 5-person example.
    const ownerId = 'you';
    const sarah = 'sarah-uuid';
    const alex = 'alex-uuid';
    const mike = 'mike-uuid';
    const john = 'john-contact-row-id';

    final split = BillSplitView(
      id: 'split-1',
      transactionId: 'tx-1',
      ownerId: ownerId,
      mode: BillSplitMode.byItem,
      totalMyr: 150,
      createdAt: DateTime(2026, 8, 24),
      participants: const [
        BillSplitParticipant(
          id: 'p-sarah', friendUserId: sarah, shareMyr: 35,
          paid: false, paidAt: null, lastRemindedAt: null,
        ),
        BillSplitParticipant(
          id: 'p-alex', friendUserId: alex, shareMyr: 32,
          paid: false, paidAt: null, lastRemindedAt: null,
        ),
        BillSplitParticipant(
          id: 'p-mike', friendUserId: mike, shareMyr: 28,
          paid: false, paidAt: null, lastRemindedAt: null,
        ),
        BillSplitParticipant(
          id: john, friendUserId: null, contactName: 'John', contactPhone: '60111222333',
          shareMyr: 25, paid: false, paidAt: null, lastRemindedAt: null,
        ),
      ],
      itemAssignments: const [
        BillSplitItemAssignment(lineItemId: 'item-sarah-only', assignedKey: sarah),
        BillSplitItemAssignment(lineItemId: 'item-john-only', assignedKey: john),
        BillSplitItemAssignment(lineItemId: 'item-shared', assignedKey: alex),
        BillSplitItemAssignment(lineItemId: 'item-shared', assignedKey: mike),
      ],
    );

    test("an item assigned only to a friend doesn't leak to the external contact", () {
      final assignees = split.assigneeIdsForLineItem('item-sarah-only');
      expect(assignees, [sarah]);
      expect(assignees.contains(john), false);
    });

    test("an item assigned only to the external contact doesn't leak to any friend", () {
      final assignees = split.assigneeIdsForLineItem('item-john-only');
      expect(assignees, [john]);
      expect(assignees.contains(sarah), false);
      expect(assignees.contains(alex), false);
      expect(assignees.contains(mike), false);
    });

    test('a shared item lists exactly its assignees, no more no less', () {
      final assignees = split.assigneeIdsForLineItem('item-shared');
      expect(assignees.toSet(), {alex, mike});
    });

    test('equal-mode assigneeIdsForLineItem includes the owner and every participant once', () {
      final equalSplit = split.copyWith();
      final equalModeSplit = BillSplitView(
        id: equalSplit.id,
        transactionId: equalSplit.transactionId,
        ownerId: equalSplit.ownerId,
        mode: BillSplitMode.equal,
        totalMyr: equalSplit.totalMyr,
        createdAt: equalSplit.createdAt,
        participants: equalSplit.participants,
        itemAssignments: const [],
      );
      final assignees = equalModeSplit.assigneeIdsForLineItem(null);
      expect(assignees.toSet(), {ownerId, sarah, alex, mike, john});
    });
  });
}
