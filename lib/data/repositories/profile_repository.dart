import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/bootstrap/app_prefs.dart';

/// Reads/writes the profile-setup fields on `profiles` (username, real
/// profile photo) and the local completion flag. Single file (no `_io`/`_web`
/// split) — pure Supabase calls, same shape as `avatar_repository.dart`.
class ProfileRepository {
  ProfileRepository._();

  static Future<bool> isUsernameAvailable(String username) async {
    final result = await Supabase.instance.client.rpc(
      'is_username_available',
      params: {'candidate': username},
    );
    return result as bool;
  }

  static Future<String> uploadAvatarPhoto({
    required String userId,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final ext = mimeType == 'image/png' ? 'png' : 'jpg';
    final path = '$userId/avatar.$ext';
    await Supabase.instance.client.storage
        .from('avatars')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(contentType: mimeType, upsert: true),
        );
    return Supabase.instance.client.storage.from('avatars').getPublicUrl(path);
  }

  /// Persists username/photo and marks setup complete. If [username]
  /// collides with one claimed since the last availability check, retries
  /// without it rather than blocking completion of the flow.
  static Future<void> completeProfileSetup({
    required String userId,
    String? username,
    String? avatarUrl,
  }) async {
    final update = {
      'username': ?username,
      'avatar_url': ?avatarUrl,
      'profile_setup_complete': true,
    };
    try {
      await Supabase.instance.client
          .from('profiles')
          .update(update)
          .eq('id', userId);
    } on PostgrestException catch (e) {
      if (e.code == '23505' && username != null) {
        await Supabase.instance.client
            .from('profiles')
            .update({'avatar_url': ?avatarUrl, 'profile_setup_complete': true})
            .eq('id', userId);
      } else {
        rethrow;
      }
    }
    await AppPrefs.setProfileSetupComplete();
  }

  /// Name/username/photo shown on the Settings screen header. Best-effort;
  /// nulls on failure (caller falls back to the auth email / a placeholder).
  static Future<({String? displayName, String? username, String? avatarUrl})>
  fetchProfileHeader(String userId) async {
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('display_name, username, avatar_url')
          .eq('id', userId)
          .maybeSingle();
      return (
        displayName: row?['display_name'] as String?,
        username: row?['username'] as String?,
        avatarUrl: row?['avatar_url'] as String?,
      );
    } on Object {
      return (displayName: null, username: null, avatarUrl: null);
    }
  }

  /// Updates just the profile photo — used from Settings, where the user is
  /// already past the one-time profile-setup flow.
  static Future<void> updateAvatarUrl({
    required String userId,
    required String avatarUrl,
  }) async {
    await Supabase.instance.client
        .from('profiles')
        .update({'avatar_url': avatarUrl})
        .eq('id', userId);
  }

  /// The caller's own phone number (normalized digits, see
  /// `lib/domain/logic/phone_number.dart`). Read via `get_my_phone_e164()`
  /// since direct column-level SELECT on `phone_e164` is revoked — see
  /// `20260824010000_profile_phone_identity.sql`. Null if unset or on
  /// failure (Settings just shows an empty field either way).
  static Future<String?> fetchMyPhoneE164() async {
    try {
      final result = await Supabase.instance.client.rpc('get_my_phone_e164');
      return result as String?;
    } on Object {
      return null;
    }
  }

  /// Sets or clears (pass null) the caller's phone number. [normalized]
  /// must already be in `normalizePhoneForWhatsApp` output shape — this
  /// method does no normalization itself. Returns a human-readable error on
  /// failure (most commonly a duplicate-phone conflict, Postgres `23505`
  /// against `profiles_phone_e164_unique_idx`), or null on success.
  static Future<String?> updateMyPhoneE164({
    required String userId,
    required String? normalized,
  }) async {
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'phone_e164': normalized})
          .eq('id', userId);
      return null;
    } on PostgrestException catch (e) {
      return e.code == '23505'
          ? 'That number is already linked to another account.'
          : 'Could not save phone number.';
    } on Object {
      return 'Could not save phone number.';
    }
  }

  /// Best-effort: if the server already has this account marked as having
  /// completed profile setup (e.g. it was done on another device), syncs
  /// that into the local pref so a reinstall doesn't re-show the screen.
  static Future<void> syncProfileSetupStatus(String userId) async {
    if (AppPrefs.profileSetupComplete) return;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('profile_setup_complete')
          .eq('id', userId)
          .maybeSingle();
      if (row?['profile_setup_complete'] == true) {
        await AppPrefs.setProfileSetupComplete();
      }
    } on Object {
      // Best-effort; router will show the profile-setup screen if this
      // failed and the flag is genuinely still unset.
    }
  }
}
