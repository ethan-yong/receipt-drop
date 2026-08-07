import 'package:flutter/material.dart';

import '../../core/platform/adaptive_sheet.dart';
import '../../core/theme/bill_split_theme.dart';
import '../../data/repositories/bill_split_repository.dart';
import '../../data/repositories/social_repository.dart';
import '../../widgets/receipt_sheet_widgets.dart';
import 'person_avatar.dart';

/// Launches [CreateGroupSheet] as a nested `AdaptiveSheet.showForm` over
/// the Bill Split sheet. Returns `true` if a group was created.
abstract final class CreateGroupSheetLauncher {
  static Future<bool> launch(
    BuildContext context, {
    required List<FriendshipView> friends,
  }) async {
    final result = await AdaptiveSheet.showForm<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: BillSplitColors.surface,
      topRadius: kReceiptSheetRadius,
      showDragHandle: false,
      child: CreateGroupSheet(friends: friends),
    );
    return result ?? false;
  }
}

/// Name a new [FriendGroupView] and pick its members, reusing the friend
/// roster already loaded by `BillSplitSheet`. v1 is create-only — no
/// rename/edit-members UI.
class CreateGroupSheet extends StatefulWidget {
  const CreateGroupSheet({super.key, required this.friends});

  final List<FriendshipView> friends;

  @override
  State<CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<CreateGroupSheet> {
  final _nameController = TextEditingController();
  final Set<String> _selected = {};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await BillSplitRepository.createFriendGroup(
      name: _nameController.text,
      memberFriendUserIds: _selected.toList(),
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'New group',
              textAlign: TextAlign.center,
              style: balooText(17, FontWeight.w800, color: BillSplitColors.ink),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(hintText: 'Group name (e.g. Roommates)'),
              style: balooText(15, FontWeight.w700, color: BillSplitColors.ink),
            ),
            const SizedBox(height: 16),
            if (widget.friends.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Add friends first to build a group.',
                  style: balooText(13, FontWeight.w600, color: BillSplitColors.sub),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final f in widget.friends)
                      _MemberRow(
                        friendship: f,
                        selected: _selected.contains(f.otherUserId),
                        onTap: () => setState(() {
                          if (!_selected.remove(f.otherUserId)) {
                            _selected.add(f.otherUserId);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: balooText(13, FontWeight.w600, color: const Color(0xFFC0392B)),
              ),
            ],
            const SizedBox(height: 16),
            _saving
                ? const Center(
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  )
                : ReceiptSheetCta(
                    label: 'Create group',
                    onPressed: (_nameController.text.trim().isNotEmpty &&
                            _selected.isNotEmpty)
                        ? _save
                        : null,
                  ),
          ],
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.friendship, required this.selected, required this.onTap});

  final FriendshipView friendship;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            PersonAvatar(
              isYou: false,
              displayName: friendship.otherDisplayName,
              avatarConfigJson: friendship.otherAvatarConfigJson,
              size: 36,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                friendship.otherDisplayName ?? 'Friend',
                style: balooText(14.5, FontWeight.w700, color: BillSplitColors.ink),
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? BillSplitColors.gold : BillSplitColors.checkboxBorder,
            ),
          ],
        ),
      ),
    );
  }
}
