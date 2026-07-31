import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads the package name of the app that initiated the current OS share
/// intent, when the platform exposes one — best-effort, never a dependency
/// for the rest of the share flow. See
/// `docs/plans/2026-07-30-post-share-receipt-notification.md`.
///
/// Android only: backed by `Activity.getReferrer()` via a small native
/// addition in `MainActivity.kt` (the `receive_sharing_intent` plugin
/// doesn't expose this itself). iOS has no equivalent API for identifying
/// the app that started a standard share sheet action, so this always
/// returns `null` there — that's an iOS platform limitation, not a bug.
abstract final class ShareReferrerReader {
  static const _channel =
      MethodChannel('com.receiptdrop.receipt_drop/share_referrer');

  static Future<String?> readReferrerPackage() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      final pkg = await _channel.invokeMethod<String>('getReferrerPackage');
      return (pkg == null || pkg.isEmpty) ? null : pkg;
    } on Object {
      // Best-effort only — a missing/failing channel must never block
      // saving the shared receipt.
      return null;
    }
  }
}
