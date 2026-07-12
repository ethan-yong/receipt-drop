import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../core/platform/platform_feedback.dart';
import '../../core/routing/app_router.dart';
import '../pending_imports/pending_import_service.dart';

/// Listens for OS share intents and routes them through the ingest pipeline.
class ShareIntentListener extends StatefulWidget {
  const ShareIntentListener({super.key, required this.child});

  final Widget child;

  @override
  State<ShareIntentListener> createState() => _ShareIntentListenerState();
}

class _ShareIntentListenerState extends State<ShareIntentListener> {
  StreamSubscription<List<SharedMediaFile>>? _subscription;

  bool get _supportsShareIntent {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    if (!_supportsShareIntent) return;
    _listenForShares();
  }

  Future<void> _listenForShares() async {
    _subscription =
        ReceiveSharingIntent.instance.getMediaStream().listen(_handleSharedFiles);

    final initial = await ReceiveSharingIntent.instance.getInitialMedia();
    if (initial.isNotEmpty) {
      await _handleSharedFiles(initial);
    }
  }

  Future<void> _handleSharedFiles(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;

    final file = files.firstWhere(
      (f) =>
          f.type == SharedMediaType.image ||
          f.type == SharedMediaType.file ||
          f.type == SharedMediaType.video,
      orElse: () => files.first,
    );

    if (file.type == SharedMediaType.text || file.type == SharedMediaType.url) {
      return;
    }

    final context = rootNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    await PendingImportService.saveSharedReceipt(
      path: file.path,
      mimeType: file.mimeType ?? _guessMimeType(file.path),
    );

    if (context.mounted) {
      PlatformFeedback.showMessage(
        context,
        'Receipt saved — open Receipt Drop to review',
      );
    }

    await ReceiveSharingIntent.instance.reset();
  }

  String _guessMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
