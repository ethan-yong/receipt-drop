import 'package:flutter/material.dart';

import '../../core/platform/adaptive_sheet.dart';
import '../../core/theme/receipt_sheet_theme.dart';
import '../../data/repositories/profile_repository.dart';
import '../../domain/logic/phone_number.dart';
import '../../widgets/receipt_sheet_widgets.dart';

/// Add/edit/remove the caller's own phone number
/// (`profiles.phone_e164` — see `20260824010000_profile_phone_identity.sql`).
/// Optional, self-reported: lets a payer's Bill Split contact picker
/// recognize this account by phone, whether or not the two are already
/// friends. Launched from the "Account" row in `settings_screen.dart`.
abstract final class PhoneNumberSheet {
  static Future<void> show(BuildContext context, {required String userId}) {
    return AdaptiveSheet.showForm<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ReceiptSheetColors.background,
      topRadius: kReceiptSheetRadius,
      showDragHandle: false,
      child: _PhoneNumberSheetBody(userId: userId),
    );
  }
}

class _PhoneNumberSheetBody extends StatefulWidget {
  const _PhoneNumberSheetBody({required this.userId});

  final String userId;

  @override
  State<_PhoneNumberSheetBody> createState() => _PhoneNumberSheetBodyState();
}

class _PhoneNumberSheetBodyState extends State<_PhoneNumberSheetBody> {
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  /// Whether a number was already saved when this sheet opened — controls
  /// whether "Remove number" is shown.
  bool _hadExistingNumber = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final current = await ProfileRepository.fetchMyPhoneE164();
    if (!mounted) return;
    setState(() {
      if (current != null) {
        _controller.text = '+$current';
        _hadExistingNumber = true;
      }
      _loading = false;
    });
  }

  Future<void> _save() async {
    final normalized = normalizePhoneForWhatsApp(_controller.text);
    if (normalized == null) {
      setState(() => _error = "That doesn't look like a valid phone number");
      return;
    }
    await _persist(normalized);
  }

  Future<void> _remove() async {
    await _persist(null);
  }

  Future<void> _persist(String? normalized) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await ProfileRepository.updateMyPhoneE164(
      userId: widget.userId,
      normalized: normalized,
    );
    if (!mounted) return;
    if (error != null) {
      setState(() {
        _saving = false;
        _error = error;
      });
      return;
    }
    Navigator.of(context).pop();
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
              'Phone number',
              textAlign: TextAlign.center,
              style: balooText(17, FontWeight.w800, color: ReceiptSheetColors.heading),
            ),
            const SizedBox(height: 6),
            Text(
              "Lets friends' bill splits recognize you automatically when "
              "you're in their contacts.",
              textAlign: TextAlign.center,
              style: balooText(
                12.5,
                FontWeight.w600,
                color: ReceiptSheetColors.subLight,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                decoration: BoxDecoration(
                  color: ReceiptSheetColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _error != null ? ReceiptSheetColors.error : ReceiptSheetColors.handle,
                    width: 2,
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  keyboardType: TextInputType.phone,
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                  style: balooText(16, FontWeight.w700, color: ReceiptSheetColors.heading),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '+60 12 345 6789',
                    hintStyle: balooText(16, FontWeight.w700, color: ReceiptSheetColors.subLight),
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    _error!,
                    style: balooText(13, FontWeight.w700, color: ReceiptSheetColors.error),
                  ),
                ),
              const SizedBox(height: 18),
              _saving
                  ? const Center(
                      child: SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    )
                  : ReceiptSheetCta(label: 'Save', onPressed: _save),
              if (_hadExistingNumber && !_saving) ...[
                const SizedBox(height: 10),
                ReceiptSheetLink(
                  label: 'Remove number',
                  color: ReceiptSheetColors.subLight,
                  onTap: _remove,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
