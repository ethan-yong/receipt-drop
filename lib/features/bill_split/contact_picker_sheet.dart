import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:uuid/uuid.dart';

import '../../core/platform/adaptive_sheet.dart';
import '../../core/theme/bill_split_theme.dart';
import '../../domain/logic/phone_number.dart';
import '../../domain/models/bill_split.dart';
import '../../widgets/receipt_sheet_widgets.dart';
import 'person_avatar.dart';

enum _PickerStatus { loading, needsPermission, permanentlyDenied, ready }

/// Lets the payer pick people from their phone's own contacts to split a
/// bill with, without requiring a Receipt Drop account. Launched from
/// "Add from contacts" in [BillSplitStepWho] (mobile only — device contact
/// access has no meaningful Web/Desktop equivalent here).
abstract final class ContactPickerSheet {
  /// Returns the newly picked contacts, or null if the sheet was dismissed
  /// without confirming. [alreadySelectedPhones] (normalized digits) are
  /// excluded from the list — best-effort dedup against contacts already
  /// added to this split (see the plan's "Known limitations": this never
  /// cross-checks against Receipt Drop friends, who have no stored phone).
  static Future<List<ExternalContactDraft>?> show(
    BuildContext context, {
    required Set<String> alreadySelectedPhones,
  }) {
    return AdaptiveSheet.showForm<List<ExternalContactDraft>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BillSplitColors.surface,
      topRadius: kReceiptSheetRadius,
      showDragHandle: false,
      child: _ContactPickerBody(alreadySelectedPhones: alreadySelectedPhones),
    );
  }
}

class _ContactPickerBody extends StatefulWidget {
  const _ContactPickerBody({required this.alreadySelectedPhones});

  final Set<String> alreadySelectedPhones;

  @override
  State<_ContactPickerBody> createState() => _ContactPickerBodyState();
}

class _ContactPickerBodyState extends State<_ContactPickerBody> {
  static const _uuid = Uuid();

  _PickerStatus _status = _PickerStatus.loading;
  List<Contact> _contacts = const [];
  String _query = '';
  final Map<String, String> _selectedPhoneById = {}; // contact.id -> chosen phone digits

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
    final drafts = <ExternalContactDraft>[];
    final seenPhones = {...widget.alreadySelectedPhones};
    for (final contact in _contacts) {
      final rawPhone = _selectedPhoneById[contact.id];
      if (rawPhone == null) continue;
      final normalized = normalizePhoneForWhatsApp(rawPhone);
      if (normalized == null || seenPhones.contains(normalized)) continue;
      seenPhones.add(normalized);
      drafts.add(ExternalContactDraft(
        id: _uuid.v4(),
        name: contact.displayName,
        phoneDigits: normalized,
      ));
    }
    Navigator.of(context).pop(drafts);
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
    required this.onTap,
    required this.onPhoneChanged,
  });

  final Contact contact;
  final bool selected;
  final String? selectedPhone;
  final VoidCallback onTap;
  final ValueChanged<String> onPhoneChanged;

  @override
  Widget build(BuildContext context) {
    final phones = contact.phones;
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
                      if (phones.isNotEmpty)
                        Text(
                          selectedPhone ?? phones.first.number,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: balooText(12.5, FontWeight.w600, color: BillSplitColors.subLight),
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
          // the right one ends up in the WhatsApp reminder — otherwise the
          // first number is used by default.
          if (selected && phones.length > 1)
            Padding(
              padding: const EdgeInsets.only(left: 52, top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final phone in phones)
                    ChoiceChip(
                      label: Text(phone.number),
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
