import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/models/receipt_display_image.dart';
import '../../widgets/skeleton.dart';

/// Full-screen pinch/pan viewer for a receipt photo.
///
/// Pattern-matched on PlacePickerScreen's rootNavigator + fullscreenDialog
/// + Stack/overlay-bar shape (without the place-picker bottom sheet).
class ReceiptImageViewerScreen extends StatelessWidget {
  const ReceiptImageViewerScreen({
    super.key,
    required this.image,
    this.mimeType,
    this.onRetake,
  });

  final ReceiptDisplayImage image;
  final String? mimeType;
  final VoidCallback? onRetake;

  static Future<void> push(
    BuildContext context, {
    required ReceiptDisplayImage image,
    String? mimeType,
    VoidCallback? onRetake,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ReceiptImageViewerScreen(
          image: image,
          mimeType: mimeType,
          onRetake: onRetake,
        ),
      ),
    );
  }

  bool get _isPdf {
    final mime = mimeType?.toLowerCase() ?? '';
    if (mime.contains('pdf')) return true;
    final path = image.localPath?.toLowerCase() ?? '';
    return path.endsWith('.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(child: _buildBody()),
          _buildTopBar(context),
          if (onRetake != null) _buildBottomBar(context),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (!image.isAvailable) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Photo not available on this device yet',
            style: TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_isPdf) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.picture_as_pdf, color: Colors.white70, size: 48),
              SizedBox(height: 12),
              Text(
                "PDF receipts can't be zoomed here. Use Retake to capture a photo instead.",
                style: TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4,
      child: Center(child: _buildImage()),
    );
  }

  Widget _buildImage() {
    if (image.localPath != null &&
        image.localPath!.isNotEmpty &&
        !image.localPath!.startsWith('web:')) {
      return Image.file(
        File(image.localPath!),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Icon(
          Icons.broken_image_outlined,
          color: Colors.white54,
          size: 48,
        ),
      );
    }
    if (image.imageUrl != null && image.imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: image.imageUrl!,
        fit: BoxFit.contain,
        placeholder: (_, _) => const Skeleton(
          child: SkeletonBox(
            width: 200,
            height: 280,
            radius: 0,
          ),
        ),
        errorWidget: (_, _, _) => const Icon(
          Icons.broken_image_outlined,
          color: Colors.white54,
          size: 48,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildTopBar(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Row(
          children: [
            _ViewerCircleButton(
              icon: Icons.close,
              onTap: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                onRetake?.call();
              },
              icon: const Icon(Icons.camera_alt_outlined),
              label: const Text('Retake'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewerCircleButton extends StatelessWidget {
  const _ViewerCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}
