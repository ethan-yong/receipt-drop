import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/pending_import_model.dart';
import '../../widgets/skeleton.dart';
import '../share/batch_scan_progress.dart';
import 'pending_import_service.dart';

class PendingImportsScreen extends StatelessWidget {
  const PendingImportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: const Text('Receipts Waiting'),
        actions: [
          StreamBuilder<List<PendingImportModel>>(
            stream: AppServices.pendingImports.watchAll(),
            builder: (context, snapshot) {
              final imports = snapshot.data ?? const [];
              final processable =
                  imports.where((i) => i.status == 'local').toList();
              if (processable.length < 2) return const SizedBox.shrink();
              return TextButton(
                onPressed: () => _processAll(context, processable),
                child: const Text('Process all'),
              );
            },
          ),
        ],
      ),
      body: StreamBuilder<List<PendingImportModel>>(
        stream: AppServices.pendingImports.watchAll(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _PendingImportsSkeleton();
          }

          final imports = snapshot.data ?? const [];
          if (imports.isEmpty) {
            return _EmptyState();
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            itemCount: imports.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) => _PendingImportCard(
              import: imports[index],
              onProcess: () =>
                  PendingImportService.processImport(context, imports[index]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _processAll(
    BuildContext context,
    List<PendingImportModel> imports,
  ) async {
    var progress = BatchScanProgress(totalCount: imports.length);
    for (final import in imports) {
      if (!context.mounted) return;
      progress = await PendingImportService.processImport(
            context,
            import,
            batchProgress: progress,
          ) ??
          progress;
    }
  }
}

class _PendingImportsSkeleton extends StatelessWidget {
  const _PendingImportsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeleton(
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, _) => const _PendingImportCardSkeleton(),
      ),
    );
  }
}

class _PendingImportCardSkeleton extends StatelessWidget {
  const _PendingImportCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: const Row(
          children: [
            SkeletonBox(width: 64, height: 64, radius: 8),
            SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 70, height: 16, radius: 10),
                  SizedBox(height: AppSpacing.xs),
                  SkeletonBox(width: 110, height: 12),
                ],
              ),
            ),
            SizedBox(width: AppSpacing.sm),
            SkeletonBox(width: 72, height: 32, radius: 20),
          ],
        ),
      ),
    );
  }
}

class _PendingImportCard extends StatelessWidget {
  const _PendingImportCard({
    required this.import,
    required this.onProcess,
  });

  final PendingImportModel import;
  final VoidCallback onProcess;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Row(
          children: [
            _Thumbnail(import: import),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (import.sourceApp != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.badgeNeedsAmountBg,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.chipRadius),
                      ),
                      child: Text(
                        import.sourceApp!,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppColors.badgeNeedsAmountText,
                            ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                  ],
                  Text(
                    DateFormat('d MMM, h:mm a').format(import.createdAt.toLocal()),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                  if (import.isFailed) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Could not read — tap Retry',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppColors.destructive,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            if (import.isProcessing)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              FilledButton(
                onPressed: onProcess,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(AppSpacing.buttonRadius),
                  ),
                  backgroundColor: import.isFailed
                      ? AppColors.destructive
                      : null,
                ),
                child: Text(import.isFailed ? 'Retry' : 'Process'),
              ),
          ],
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.import});

  final PendingImportModel import;

  @override
  Widget build(BuildContext context) {
    const size = 64.0;
    const radius = BorderRadius.all(Radius.circular(AppSpacing.sm));

    if (import.mimeType.contains('pdf')) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.creamDark,
          borderRadius: radius,
        ),
        child: const Icon(Icons.picture_as_pdf_outlined, size: 28),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: Image.file(
        File(import.localFilePath),
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
            color: AppColors.creamDark,
            borderRadius: radius,
          ),
          child: const Icon(Icons.receipt_outlined, size: 28),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 64,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'No receipts waiting',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Share a receipt from any app and it will appear here',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textMuted,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
