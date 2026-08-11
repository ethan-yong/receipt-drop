import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/receipt_sheet_theme.dart';
import '../../data/repositories/profile_repository.dart';

/// Profile setup screen shown right after Google sign-in (approved design,
/// `Profile Setup Onboarding.dc.html`). Lets the user pick a photo and claim
/// an `@username` before entering the app; both are optional (Skip).
class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _usernameController = TextEditingController();
  Uint8List? _photoBytes;
  String? _photoMimeType;
  bool _usernameTaken = false;
  bool _submitting = false;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photoBytes = bytes;
        _photoMimeType = file.mimeType ?? 'image/jpeg';
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not load photo: $e')));
      }
    }
  }

  Future<void> _showPhotoSourceSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ReceiptSheetColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(
                Icons.camera_alt_outlined,
                color: ReceiptSheetColors.ink,
              ),
              title: Text(
                'Take photo',
                style: balooText(
                  15,
                  FontWeight.w700,
                  color: ReceiptSheetColors.ink,
                ),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_outlined,
                color: ReceiptSheetColors.ink,
              ),
              title: Text(
                'Choose from library',
                style: balooText(
                  15,
                  FontWeight.w700,
                  color: ReceiptSheetColors.ink,
                ),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickPhoto(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  Future<String?> _uploadPhotoIfPicked() async {
    final bytes = _photoBytes;
    final mimeType = _photoMimeType;
    final userId = _userId;
    if (bytes == null || mimeType == null || userId == null) return null;
    return ProfileRepository.uploadAvatarPhoto(
      userId: userId,
      bytes: bytes,
      mimeType: mimeType,
    );
  }

  Future<void> _onContinue() async {
    final userId = _userId;
    final username = _usernameController.text.trim();
    if (username.isEmpty || _submitting || userId == null) return;

    setState(() {
      _submitting = true;
      _usernameTaken = false;
    });
    try {
      final available = await ProfileRepository.isUsernameAvailable(username);
      if (!available) {
        if (mounted) setState(() => _usernameTaken = true);
        return;
      }
      final avatarUrl = await _uploadPhotoIfPicked();
      await ProfileRepository.completeProfileSetup(
        userId: userId,
        username: username,
        avatarUrl: avatarUrl,
      );
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save profile: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _onSkip() async {
    final userId = _userId;
    final username = _usernameController.text.trim();
    if (username.isEmpty || _submitting || userId == null) return;

    setState(() => _submitting = true);
    try {
      final avatarUrl = await _uploadPhotoIfPicked();
      await ProfileRepository.completeProfileSetup(
        userId: userId,
        username: username,
        avatarUrl: avatarUrl,
      );
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save profile: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canProceed = _usernameController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: ReceiptSheetColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
          child: Column(
            children: [
              const SizedBox(height: 8),
              // logo lockup
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: ReceiptSheetColors.gold,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.receipt_long,
                      size: 15,
                      color: ReceiptSheetColors.ink,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Receipt Drop',
                    style: balooText(
                      15,
                      FontWeight.w800,
                      color: ReceiptSheetColors.sub,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // avatar
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 160,
                    height: 160,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ReceiptSheetColors.tile,
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x2E3C2814),
                          blurRadius: 26,
                          offset: Offset(0, 10),
                        ),
                      ],
                      image: _photoBytes != null
                          ? DecorationImage(
                              image: MemoryImage(_photoBytes!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: _photoBytes == null
                        ? Text(
                            'Add photo',
                            style: balooText(
                              13,
                              FontWeight.w600,
                              color: ReceiptSheetColors.subLight,
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: _PressScale(
                      onTap: _showPhotoSourceSheet,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ReceiptSheetColors.gold,
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x333C2814),
                              blurRadius: 10,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          _photoBytes != null
                              ? Icons.check_rounded
                              : Icons.camera_alt_outlined,
                          size: _photoBytes != null ? 19 : 17,
                          color: ReceiptSheetColors.ink,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 26),

              Text(
                'How should friends see you?',
                textAlign: TextAlign.center,
                style: balooText(
                  22,
                  FontWeight.w800,
                  color: ReceiptSheetColors.heading,
                  letterSpacing: -0.3,
                ),
              ),

              const SizedBox(height: 18),

              // username field
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: ReceiptSheetColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _usernameTaken
                            ? ReceiptSheetColors.error
                            : ReceiptSheetColors.handle,
                        width: 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '@',
                          style: balooText(
                            16,
                            FontWeight.w700,
                            color: ReceiptSheetColors.subLight,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextField(
                            controller: _usernameController,
                            onChanged: (_) =>
                                setState(() => _usernameTaken = false),
                            style: balooText(
                              16,
                              FontWeight.w700,
                              color: ReceiptSheetColors.heading,
                              letterSpacing: -0.2,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              hintText: 'username',
                              hintStyle: balooText(
                                16,
                                FontWeight.w700,
                                color: ReceiptSheetColors.subLight,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_usernameTaken)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            "That username's already taken",
                            style: balooText(
                              13,
                              FontWeight.w700,
                              color: ReceiptSheetColors.error,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 18),

              // continue CTA
              _PressScale(
                onTap: canProceed && !_submitting ? _onContinue : null,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: canProceed
                        ? ReceiptSheetColors.gold
                        : ReceiptSheetColors.background,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: canProceed
                        ? const [
                            BoxShadow(
                              color: ReceiptSheetColors.ctaShadow,
                              blurRadius: 22,
                              offset: Offset(0, 10),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: _submitting
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: canProceed
                                ? ReceiptSheetColors.ctaText
                                : ReceiptSheetColors.subLight,
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Continue',
                              style: balooText(
                                16,
                                FontWeight.w800,
                                color: canProceed
                                    ? ReceiptSheetColors.ctaText
                                    : ReceiptSheetColors.subLight,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.arrow_forward,
                              size: 18,
                              color: canProceed
                                  ? ReceiptSheetColors.ctaText
                                  : ReceiptSheetColors.subLight,
                            ),
                          ],
                        ),
                ),
              ),

              const SizedBox(height: 12),

              _PressScale(
                onTap: canProceed && !_submitting ? _onSkip : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Skip for now',
                    style: balooText(
                      14,
                      FontWeight.w700,
                      color: canProceed
                          ? ReceiptSheetColors.linkStrong
                          : ReceiptSheetColors.handle,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared tap feedback: quick scale-down/up, 150ms ease-in-out — matches the
/// same private helper in `auth_screen.dart`.
class _PressScale extends StatefulWidget {
  const _PressScale({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null
          ? null
          : (_) => setState(() => _pressed = true),
      onTapCancel: widget.onTap == null
          ? null
          : () => setState(() => _pressed = false),
      onTapUp: widget.onTap == null
          ? null
          : (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        child: widget.child,
      ),
    );
  }
}
