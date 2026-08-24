import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:uuid/uuid.dart';

import '../../core/platform/adaptive_sheet.dart';
import '../../core/theme/bill_split_theme.dart';
import '../../data/repositories/social_repository.dart';
import '../../domain/logic/phone_number.dart';
import '../../domain/models/bill_split.dart';
import '../../widgets/receipt_sheet_widgets.dart';
import 'person_avatar.dart';

enum _PickerStatus { loading, needsPermission, permanentlyDenied, ready }

/// Lets the payer pick people from their phone's own contacts to split a
/// bill with. A picked number is resolved against existing Receipt Drop
/// accounts ([SocialRepository.findUsersByPhones]) — a match (friend or
/// not) is returned as a [MatchedContactResolution] so the caller adds them
/// as a normal friend-shaped participant with in-app reminders; no match
/// falls back to Phase 1's [UnmatchedContactResolution] (a plain
/// [ExternalContactDraft], WhatsApp reminder). Launched from "Add from
/// contacts" in [BillSplitStepWho] (mobile only — device contact access has
/// no meaningful Web/Desktop equivalent here).
abstract final class ContactPickerSheet {
  /// Returns the resolved selections, or null if the sheet was dismissed
  /// without confirming. [alreadySelectedPhones] (normalized digits) dedupes
  /// against unmatched contacts already added to this split.
  /// [alreadySelectedFriendIds] dedupes a phone match against friend rows
  /// already picked (manually or via an earlier match). [friendUserIds] is
  /// the caller's already-loaded accepted-friend id set, used only to badge
  /// a match as "Already your friend" vs. "Receipt Drop user" — it never
  /// gates whether a match can be selected.
  static Future<List<ContactResolution>?> show(
    BuildContext context, {
    required Set<String> alreadySelectedPhones,
    required Set<String> alreadySelectedFriendIds,
    required Set<String> friendUserIds,
  }) {
    return AdaptiveSheet.showForm<List<ContactResolution>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BillSplitColors.surface,
      topRadius: kReceiptSheetRadius,
      showDragHandle: false,
      child: _ContactPickerBody(
        alreadySelectedPhones: alreadySelectedPhones,
        alreadySelectedFriendIds: alreadySelectedFriendIds,
        friendUserIds: friendUserIds,
      ),
    );
  }
}

class _ContactPickerBody extends StatefulWidget {
  const _ContactPickerBody({
    required this.alreadySelectedPhones,
    required this.alreadySelectedFriendIds,
    required this.friendUserIds,
  });

  final Set<String> alreadySelectedPhones;
  final Set<String> alreadySelectedFriendIds;
  final Set<String> friendUserIds;

  @override
  State<_ContactPickerBody> createState() => _ContactPickerBodyState();
}

class _ContactPickerBodyState extends State<_ContactPickerBody> {
  static const _uuid = Uuid();

  _PickerStatus _status = _PickerStatus.loading;
  List<Contact> _contacts = const [];
  String _query = '';
  final Map<String, String> _selectedPhoneById = {}; // contact.id -> chosen phone digits

  /// normalized phone digits -> resolved Receipt Drop match. Sheet-lifetime
  /// only (a plain State field, discarded on close) — no persistent
  /// client-side phone directory.
  Map<String, PhoneMatchedUser> _matchByPhone = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final permission = await ph.Permission.contacts.status;
    if (permission.isGranted) {
      await _loadContacts();
      return;
    }
    if (permission.isPermanentlyDenied) {
      if (mounted) setState(() => _status = _PickerStatus.permanentlyDenied);
      return;
    }
    if (mounted) setState(() => _status = _PickerStatus.needsPermission);
  }

  Future<void> _requestPermission() async {
    setState(() => _status = _PickerStatus.loading);
    final granted = await FlutterContacts.requestPermission();
    if (!mounted) return;
    if (!granted) {
      final status = await ph.Permission.contacts.status;
      setState(() => _status =
          status.isPermanentlyDenied ? _PickerStatus.permanentlyDenied : _PickerStatus.needsPermission);
      return;
    }
    await _loadContacts();
  }

  Future<void> _loadContacts() async {
    final contacts = await FlutterContacts.getContacts(withProperties: true);
    if (!mounted) return;
    contacts.sort((a, b) => a.displayName.compareTo(b.displayName));
    setState(() {
      _contacts = contacts;
      _status = _PickerStatus.ready;
    });
    // Fired after the list is already rendered, so badges pop in once
    // resolved rather than blocking the whole sheet on network.
    unawaited(_resolveMatches(contacts));
  }

  Future<void> _resolveMatches(List<Contact> contacts) async {
    final normalized = <String>{};
    for (final contact in contacts) {
      for (final phone in contact.phones) {
        final n = normalizePhoneForWhatsApp(phone.number);
        if (n != null) normalized.add(n);
      }
    }
    if (normalized.isEmpty) return;
    final matches = await SocialRepository.findUsersByPhones(normalized.toList());
    if (!mounted || matches.isEmpty) return;
    setState(() {
      _matchByPhone = {for (final m in matches) m.phoneDigits: m};
    });
  }

  List<Contact> get _filtered {
    final query = _query.trim().toLowerCase();
    final withPhones = _contacts.where((c) => c.phones.isNotEmpty);
    if (query.isEmpty) return withPhones.toList();
    return withPhones.where((c) {
      if (c.displayName.toLowerCase().contains(query)) return true;
      return c.phones.any((p) => p.number.replaceAll(RegExp(r'[^0-9]'), '').contains(query));
    }).toList();
  }

  void _toggle(Contact contact) {
    setState(() {
      if (_selectedPhoneById.remove(contact.id) == null) {
        _selectedPhoneById[contact.id] = contact.phones.first.number;
      }
    });
  }

  void _setPhoneFor(Contact contact, String phoneNumber) {
    setState(() => _selectedPhoneById[contact.id] = phoneNumber);
  }

  void _confirm() {
    final results = <ContactResolution>[];
    final seenPhones = {...widget.alreadySelectedPhones};
    final seenUserIds = {...widget.alreadySelectedFriendIds};
    for (final contact in _contacts) {
      final rawPhone = _selectedPhoneById[contact.id];
      if (rawPhone == null) continue;
      final normalized = normalizePhoneForWhatsApp(rawPhone);
      if (normalized == null) continue;
      final match = _matchByPhone[normalized];
      if (match != null) {
        if (seenUserIds.contains(match.userId)) continue;
        seenUserIds.add(match.userId);
        results.add(MatchedContactResolution(
          userId: match.userId,
          displayName: match.displayName,
          avatarUrl: match.avatarUrl,
        ));
      } else {
        if (seenPhones.contains(normalized)) continue;
        seenPhones.add(normalized);
        results.add(UnmatchedContactResolution(ExternalContactDraft(
          id: _uuid.v4(),
          name: contact.displayName,
          phoneDigits: normalized,
        )));
      }
    }
    Navigator.of(context).pop(results);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.86,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Column(
            children: [
              Text(
                'Add from contacts',
                style: balooText(17, FontWeight.w800, color: BillSplitColors.ink),
              ),
              const SizedBox(height: 16),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_status) {
      case _PickerStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case _PickerStatus.needsPermission:
        return _PermissionPrompt(
          message: "Receipt Drop needs access to your contacts so you can split a bill "
              "with people who don't have the app.",
          ctaLabel: 'Allow contacts access',
          onTap: _requestPermission,
        );
      case _PickerStatus.permanentlyDenied:
        return _PermissionPrompt(
          message: 'Contacts access is turned off for Receipt Drop. Enable it in Settings '
              'to add people from your phone contacts.',
          ctaLabel: 'Open Settings',
          onTap: ph.openAppSettings,
        );
      case _PickerStatus.ready:
        return _buildList();
    }
  }

  Widget _buildList() {
    final filtered = _filtered;
    return Column(
      children: [
        TextField(
          decoration: const InputDecoration(hintText: 'Search name or phone number'),
          style: balooText(15, FontWeight.w700, color: BillSplitColors.ink),
          onChanged: (v) => setState(() => _query = v),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    'No contacts found.',
                    style: balooText(13, FontWeight.w600, color: BillSplitColors.sub),
                  ),
                )
              : ListView(
                  children: [
                    for (final contact in filtered)
                      _ContactPickRow(
                        contact: contact,
                        selected: _selectedPhoneById.containsKey(contact.id),
                        selectedPhone: _selectedPhoneById[contact.id],
                        matchByPhone: _matchByPhone,
                        friendUserIds: widget.friendUserIds,
                        onTap: () => _toggle(contact),
                        onPhoneChanged: (phone) => _setPhoneFor(contact, phone),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        ReceiptSheetCta(
          label: _selectedPhoneById.isEmpty
              ? 'Add contacts'
              : 'Add ${_selectedPhoneById.length} ${_selectedPhoneById.length == 1 ? 'contact' : 'contacts'}',
          onPressed: _selectedPhoneById.isNotEmpty ? _confirm : null,
        ),
      ],
    );
  }
}

class _PermissionPrompt extends StatelessWidget {
  const _PermissionPrompt({
    required this.message,
    required this.ctaLabel,
    required this.onTap,
  });

  final String message;
  final String ctaLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: balooText(13.5, FontWeight.w600, color: BillSplitColors.sub),
          ),
          const SizedBox(height: 18),
          ReceiptSheetCta(label: ctaLabel, onPressed: onTap),
        ],
      ),
    );
  }
}

class _ContactPickRow extends StatelessWidget {
  const _ContactPickRow({
    required this.contact,
    required this.selected,
    required this.selectedPhone,
    required this.matchByPhone,
    required this.friendUserIds,
    required this.onTap,
    required this.onPhoneChanged,
  });

  final Contact contact;
  final bool selected;
  final String? selectedPhone;
  final Map<String, PhoneMatchedUser> matchByPhone;
  final Set<String> friendUserIds;
  final VoidCallback onTap;
  final ValueChanged<String> onPhoneChanged;

  /// "Already your friend" / "Receipt Drop user" / null (no match) for one
  /// raw device-contact number.
  String? _badgeFor(String rawPhoneNumber) {
    final normalized = normalizePhoneForWhatsApp(rawPhoneNumber);
    if (normalized == null) return null;
    final match = matchByPhone[normalized];
    if (match == null) return null;
    return friendUserIds.contains(match.userId) ? 'Already your friend' : 'Receipt Drop user';
  }

  @override
  Widget build(BuildContext context) {
    final phones = contact.phones;
    final currentPhone = selectedPhone ?? (phones.isNotEmpty ? phones.first.number : null);
    final currentBadge = currentPhone != null ? _badgeFor(currentPhone) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onTap,
            child: Row(
              children: [
                PersonAvatar(
                  avatarUrl: null,
                  displayName: contact.displayName,
                  userId: contact.id,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: balooText(15, FontWeight.w800, color: BillSplitColors.ink),
                      ),
                      if (currentPhone != null)
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                currentPhone,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: balooText(12.5, FontWeight.w600, color: BillSplitColors.subLight),
                              ),
                            ),
                            if (currentBadge != null) ...[
                              const SizedBox(width: 6),
                              _MatchBadge(label: currentBadge),
                            ],
                          ],
                        ),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: selected ? BillSplitColors.gold : Colors.white,
                    border: Border.all(
                      color: selected ? BillSplitColors.gold : BillSplitColors.checkboxBorder,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  alignment: Alignment.center,
                  child: selected ? const Icon(Icons.check, size: 15, color: Colors.white) : null,
                ),
              ],
            ),
          ),
          // A contact with multiple numbers gets an inline chip picker so
          // the right one ends up as the participant — each chip shows its
          // own match badge so the choice can be informed before picking,
          // not just after.
          if (selected && phones.length > 1)
            Padding(
              padding: const EdgeInsets.only(left: 52, top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final phone in phones)
                    ChoiceChip(
                      label: Text(
                        [phone.number, ?_badgeFor(phone.number)].join(' · '),
                      ),
                      selected: selectedPhone == phone.number,
                      onSelected: (_) => onPhoneChanged(phone.number),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MatchBadge extends StatelessWidget {
  const _MatchBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: BillSplitColors.gold.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: balooText(10.5, FontWeight.w800, color: BillSplitColors.ink),
      ),
    );
  }
}
