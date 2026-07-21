import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'receipt_thumbnail_file.dart'
    if (dart.library.html) 'receipt_thumbnail_file_web.dart' as file_image;
import 'skeleton.dart';

class ReceiptThumbnail extends StatelessWidget {
  const ReceiptThumbnail({
    super.key,
    this.imageUrl,
    this.localPath,
    this.thumbnailBytes,
    this.size = 48,
    this.radius = 10,
  });

  final String? imageUrl;
  final String? localPath;
  final Uint8List? thumbnailBytes;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: _buildImage(),
      ),
    );
  }

  Widget _buildImage() {
    if (thumbnailBytes != null && thumbnailBytes!.isNotEmpty) {
      return Image.memory(
        thumbnailBytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
      );
    }
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: imageUrl!,
        fit: BoxFit.cover,
        placeholder: (_, _) => _loadingPlaceholder(),
        errorWidget: (_, _, _) => _placeholder(),
      );
    }
    if (localPath != null &&
        localPath!.isNotEmpty &&
        !localPath!.startsWith('web:')) {
      return file_image.buildLocalFileImage(
        localPath!,
        placeholder: _placeholder(),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.divider,
      child: const Icon(
        Icons.receipt_long_outlined,
        color: AppColors.textMuted,
        size: 24,
      ),
    );
  }

  /// Shown only while the network image is in flight — genuinely transient,
  /// unlike [_placeholder] which also covers permanent "nothing to show"
  /// states (error, no image at all).
  Widget _loadingPlaceholder() {
    return const Skeleton(
      child: SkeletonBox(width: double.infinity, height: double.infinity, radius: 0),
    );
  }
}
