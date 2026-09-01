import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/config/env.dart';
import '../../core/payment_detection/payment_event_bridge.dart';
import '../../core/payment_detection/payment_permission_prompt.dart';
import '../../core/theme/receipt_sheet_theme.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/social_repository.dart';

/// Profile / settings tab (approved design, `Settings.dc.html`) — restyled
/// onto the same warm cream/gold Baloo 2 system as the profile-setup screen,
/// with an editable profile-photo header. Shown as the Profile bottom tab.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  static const _version = '1.0.0';

  // Optimistic default (matches the server column default) while loading.
  bool _shareMapLocation = true;
  String? _displayName;
  String? _username;
  String? _avatarUrl;
  Uint8List? _pendingAvatarBytes;

  PaymentListenerStatus _listenerStatus =
      const PaymentListenerStatus.unavailable();
  bool _overlayPermissionGranted = false;
  bool _batteryOptimizationIgnored = false;
  bool _paymentDetectionEnabled = false;

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SocialRepository.getShareMapLocation().then((value) {
      if (mounted) setState(() => _shareMapLocation = value);
    });
    final userId = _userId;
    if (userId != null) {
      ProfileRepository.fetchProfileHeader(userId).then((header) {
        if (mounted) {
          setState(() {
            _displayName = header.displayName;
            _username = header.username;
            _avatarUrl = header.avatarUrl;
          });
        }
      });
    }
    _refreshPaymentDetectionPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The two permissions below are granted from a separate system Settings
    // screen with no callback into the app — re-check on resume so the
    // Granted/Not granted labels reflect what the user just did.
    if (state == AppLifecycleState.resumed) {
      _refreshPaymentDetectionPermissions();
    }
  }

  Future<void> _refreshPaymentDetectionPermissions() async {
    final enabled = await PaymentEventBridge.isPaymentDetectionEnabled();
    final listenerStatus = await PaymentEventBridge.notificationListenerStatus();
    final overlayPermission =
        await PaymentEventBridge.isOverlayPermissionGranted();
    final batteryOptimizationIgnored =
        await PaymentEventBridge.isBatteryOptimizationIgnored();
    if (mounted) {
      setState(() {
        _paymentDetectionEnabled = enabled;
        _listenerStatus = listenerStatus;
        _overlayPermissionGranted = overlayPermission;
        _batteryOptimizationIgnored = batteryOptimizationIgnored;
      });
    }
  }

  /// Master switch. Turning it on persists the choice natively (so the
  /// listener honours it) and walks the user through any missing permission;
  /// turning it off leaves the listener bound but inert.
  Future<void> _setPaymentDetectionEnabled(bool enabled) async {
    setState(() => _paymentDetectionEnabled = enabled);
    await PaymentEventBridge.setPaymentDetectionEnabled(enabled);
    if (enabled && mounted) {
      await PaymentPermissionPrompt.runSetupWalkthrough(context);
      await _refreshPaymentDetectionPermissions();
    }
  }

  String get _notificationAccessLabel => switch (_listenerStatus.state) {
    PaymentListenerState.active => 'Granted',
    PaymentListenerState.grantedButInactive => 'Inactive',
    PaymentListenerState.notGranted => 'Not granted',
  };

  void _onNotificationAccessTap() {
    if (_listenerStatus.state == PaymentListenerState.grantedButInactive) {
      _showListenerInactiveDialog();
      return;
    }
    PaymentEventBridge.openNotificationAccessSettings();
  }

  /// The permission is on but the OS never started the listener — almost
  /// always an OEM background-autostart block. Say so explicitly, because
  /// the system Settings screen the user would otherwise check will keep
  /// insisting the permission is granted.
  Future<void> _showListenerInactiveDialog() async {
    final openAutostart = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Payment detection is not running'),
        content: const Text(
          'Notification access is allowed, but your phone has not started '
          'Receipt Drop\'s listener, so payments are not being detected.\n\n'
          'This is usually the separate "Autostart" (or "Allow background '
          'activity") setting that Xiaomi, Oppo, Vivo and Huawei phones add '
          'on top of the standard permission. Turn it on for Receipt Drop, '
          'then reopen the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Notification settings'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Open autostart'),
          ),
        ],
      ),
    );
    if (openAutostart == null) return;
    if (openAutostart) {
      await PaymentEventBridge.openAutostartSettings();
    } else {
      await PaymentEventBridge.openNotificationAccessSettings();
    }
  }

  void _setShareMapLocation(bool value) {
    setState(() => _shareMapLocation = value);
    SocialRepository.setShareMapLocation(value);
  }

  Future<void> _signOut() async {
    if (!Env.hasSupabaseConfig) return;
    try {
      await Supabase.instance.client.auth.signOut();
    } on Object {
      // No session in debug/skip-auth flows.
    }
  }

  Future<void> _clearCache() async {
    await AppServices.transactions.clearAll();
    await AppServices.transactions.seedDemoDataIfEmpty();
    if (kDebugMode) {
      await AppServices.transactions.seedReceiptShowcaseIfEmpty();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local cache cleared (cloud data kept)')),
      );
    }
  }

  Future<void> _pickAvatarPhoto(ImageSource source) async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _pendingAvatarBytes = bytes);
      final url = await ProfileRepository.uploadAvatarPhoto(
        userId: userId,
        bytes: bytes,
        mimeType: file.mimeType ?? 'image/jpeg',
      );
      await ProfileRepository.updateAvatarUrl(userId: userId, avatarUrl: url);
      if (mounted) setState(() => _avatarUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not update photo: $e')));
      }
    } finally {
      if (mounted) setState(() => _pendingAvatarBytes = null);
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
                  color: ReceiptSheetColors.heading,
                ),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickAvatarPhoto(ImageSource.camera);
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
                  color: ReceiptSheetColors.heading,
                ),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _pickAvatarPhoto(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = Env.hasSupabaseConfig
        ? Supabase.instance.client.auth.currentUser?.email
        : 'Demo mode';
    final name = _displayName ?? email?.split('@').first ?? 'You';

    return Scaffold(
      backgroundColor: ReceiptSheetColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Profile',
                  style: balooText(
                    20,
                    FontWeight.w800,
                    color: ReceiptSheetColors.heading,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  Column(
                    children: [
                      const SizedBox(height: 6),
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          _PressScale(
                            onTap: _showPhotoSourceSheet,
                            child: Container(
                              width: 168,
                              height: 168,
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
                                image: _pendingAvatarBytes != null
                                    ? DecorationImage(
                                        image: MemoryImage(
                                          _pendingAvatarBytes!,
                                        ),
                                        fit: BoxFit.cover,
                                      )
                                    : (_avatarUrl != null
                                          ? DecorationImage(
                                              image: NetworkImage(_avatarUrl!),
                                              fit: BoxFit.cover,
                                            )
                                          : null),
                              ),
                              alignment: Alignment.center,
                              child:
                                  _pendingAvatarBytes == null &&
                                      _avatarUrl == null
                                  ? Text(
                                      'Profile photo',
                                      style: balooText(
                                        13,
                                        FontWeight.w600,
                                        color: ReceiptSheetColors.subLight,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                          Positioned(
                            right: -4,
                            bottom: -4,
                            child: IgnorePointer(
                              child: Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: ReceiptSheetColors.gold,
                                  border: Border.all(
                                    color: ReceiptSheetColors.background,
                                    width: 3,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x383C2814),
                                      blurRadius: 10,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.edit_outlined,
                                  size: 20,
                                  color: ReceiptSheetColors.ink,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        name,
                        style: balooText(
                          17,
                          FontWeight.w800,
                          color: ReceiptSheetColors.heading,
                          letterSpacing: -0.2,
                        ),
                      ),
                      if (_username != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          '@$_username',
                          style: balooText(
                            13.5,
                            FontWeight.w700,
                            color: ReceiptSheetColors.linkStrong,
                          ),
                        ),
                      ],
                      const SizedBox(height: 2),
                      Text(
                        email ?? '',
                        style: balooText(
                          13,
                          FontWeight.w600,
                          color: ReceiptSheetColors.sub,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Tap the photo to change it',
                        style: balooText(
                          13,
                          FontWeight.w700,
                          color: ReceiptSheetColors.linkStrong,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  _SettingsGroup(
                    rows: [
                      _SettingsRow(
                        icon: Icons.person_outline,
                        title: 'Account',
                        subtitle: email,
                        onTap: () {},
                      ),
                      _SettingsRow(
                        icon: Icons.logout,
                        title: 'Sign out',
                        danger: true,
                        onTap: _signOut,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SettingsGroup(
                    rows: [
                      _SettingsRow(
                        icon: Icons.download_outlined,
                        title: 'Export (CSV)',
                        subtitle: 'Coming in v1.1',
                        disabled: true,
                      ),
                      _SettingsRow(
                        icon: Icons.shield_outlined,
                        title: 'Privacy & Legal',
                        onTap: () {},
                      ),
                      _SettingsRow(
                        icon: Icons.location_on_outlined,
                        title: "Show me on friends' maps",
                        subtitle: 'Your latest receipt place appears as a pin',
                        toggleValue: _shareMapLocation,
                        onToggleChanged: _setShareMapLocation,
                      ),
                      _SettingsRow(
                        icon: Icons.brush_outlined,
                        title: 'Clear local cache',
                        subtitle: 'Does not delete cloud data',
                        onTap: _clearCache,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SettingsGroup(
                    rows: [
                      _SettingsRow(
                        icon: Icons.auto_awesome_outlined,
                        title: 'Payment detection',
                        subtitle:
                            'Auto-capture spending from your banking & '
                            'e-wallet notifications',
                        toggleValue: _paymentDetectionEnabled,
                        onToggleChanged: _setPaymentDetectionEnabled,
                      ),
                      if (_paymentDetectionEnabled) ...[
                        _SettingsRow(
                          icon: Icons.notifications_active_outlined,
                          title: 'Notification access',
                          subtitle:
                              _listenerStatus.state ==
                                  PaymentListenerState.grantedButInactive
                              ? 'Allowed, but your phone is blocking it from '
                                    'running — tap to fix'
                              : 'Lets Receipt Drop detect payments from '
                                    'supported banking/payment apps',
                          trailing: _notificationAccessLabel,
                          trailingWarning:
                              _listenerStatus.state ==
                                  PaymentListenerState.grantedButInactive ||
                              _listenerStatus.state ==
                                  PaymentListenerState.notGranted,
                          onTap: _onNotificationAccessTap,
                        ),
                        _SettingsRow(
                          icon: Icons.layers_outlined,
                          title: 'Display over other apps',
                          subtitle:
                              _listenerStatus.granted &&
                                  !_overlayPermissionGranted
                              ? 'Required to show the picker — payments are '
                                    'detected but nothing can appear until '
                                    'this is on'
                              : 'Shows the category picker on top of other apps',
                          trailing: _overlayPermissionGranted
                              ? 'Granted'
                              : 'Not granted',
                          trailingWarning:
                              _listenerStatus.granted &&
                              !_overlayPermissionGranted,
                          onTap: () =>
                              PaymentEventBridge.openOverlayPermissionSettings(),
                        ),
                        _SettingsRow(
                          icon: Icons.battery_saver_outlined,
                          title: 'Unrestricted battery use',
                          subtitle:
                              _listenerStatus.granted &&
                                  !_batteryOptimizationIgnored
                              ? 'Without this, payments are only detected '
                                    'when your phone next wakes up — often '
                                    'minutes or hours late'
                              : 'Detects payments right away instead of when '
                                    'your phone next wakes up',
                          trailing: _batteryOptimizationIgnored
                              ? 'Granted'
                              : 'Not granted',
                          trailingWarning:
                              _listenerStatus.granted &&
                              !_batteryOptimizationIgnored,
                          onTap: () => PaymentEventBridge
                              .requestIgnoreBatteryOptimizations(),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SettingsGroup(
                    rows: [
                      _SettingsRow(
                        icon: Icons.people_outline,
                        title: 'Friends',
                        onTap: () => context.pushNamed('friends'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SettingsGroup(
                    rows: [
                      _SettingsRow(
                        icon: Icons.info_outline,
                        title: 'App version',
                        trailing: _version,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A rounded, shadowed card of [_SettingsRow]s — clips the first/last row's
/// corners rather than each row tracking its own radius.
class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.rows});

  final List<_SettingsRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F3C2814),
            blurRadius: 10,
            offset: Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                color: ReceiptSheetColors.cardDivider,
              ),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.trailingWarning = false,
    this.onTap,
    this.danger = false,
    this.disabled = false,
    this.toggleValue,
    this.onToggleChanged,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailing;
  final bool trailingWarning;
  final VoidCallback? onTap;
  final bool danger;
  final bool disabled;
  final bool? toggleValue;
  final ValueChanged<bool>? onToggleChanged;

  bool get _isToggle => toggleValue != null;

  @override
  Widget build(BuildContext context) {
    final iconColor = danger
        ? ReceiptSheetColors.error
        : disabled
        ? ReceiptSheetColors.subLight
        : ReceiptSheetColors.ink;
    final titleColor = danger
        ? ReceiptSheetColors.error
        : disabled
        ? ReceiptSheetColors.subLight
        : ReceiptSheetColors.heading;
    final tapHandler = _isToggle
        ? () => onToggleChanged?.call(!toggleValue!)
        : onTap;

    return _PressScale(
      onTap: disabled ? null : tapHandler,
      child: Container(
        color: ReceiptSheetColors.surface,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Icon(icon, size: 22, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: balooText(
                      15.5,
                      FontWeight.w700,
                      color: titleColor,
                      letterSpacing: -0.1,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: balooText(
                        12.5,
                        FontWeight.w600,
                        color: ReceiptSheetColors.subLight,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (_isToggle)
              _ToggleSwitch(value: toggleValue!, onChanged: onToggleChanged)
            else if (trailing != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (trailingWarning) ...[
                    const Icon(
                      Icons.error_outline,
                      size: 16,
                      color: ReceiptSheetColors.error,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    trailing!,
                    style: balooText(
                      13,
                      FontWeight.w700,
                      color: trailingWarning
                          ? ReceiptSheetColors.error
                          : ReceiptSheetColors.subLight,
                    ),
                  ),
                ],
              )
            else if (onTap != null)
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: Color(0xFFD9CFBB),
              ),
          ],
        ),
      ),
    );
  }
}

class _ToggleSwitch extends StatelessWidget {
  const _ToggleSwitch({required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInOut,
      width: 46,
      height: 27,
      decoration: BoxDecoration(
        color: value ? ReceiptSheetColors.gold : ReceiptSheetColors.handle,
        borderRadius: BorderRadius.circular(14),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: 21,
          height: 21,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: ReceiptSheetColors.heading,
            boxShadow: [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared tap feedback: quick scale-down/up, 150ms ease-in-out — matches the
/// same private helper in `auth_screen.dart` / `profile_setup_screen.dart`.
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
