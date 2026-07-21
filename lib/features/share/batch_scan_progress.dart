import 'package:flutter/foundation.dart';

/// Snapshot of how far a sequential batch of receipt scans has gotten.
///
/// Threaded through [ReceiptScanProcessingScreen] instances one at a time —
/// each receipt in a "Process all" batch gets a fresh, already-updated
/// snapshot rather than sharing a mutable/listenable object, since the
/// footer only ever needs to change between receipts, never live during one
/// receipt's own animation.
@immutable
class BatchScanProgress {
  const BatchScanProgress({
    required this.totalCount,
    this.completedCount = 0,
    this.completedNames = const [],
  });

  final int totalCount;
  final int completedCount;
  final List<String> completedNames;

  String? get lastCompletedName =>
      completedNames.isEmpty ? null : completedNames.last;

  BatchScanProgress withCompleted(String name) => BatchScanProgress(
        totalCount: totalCount,
        completedCount: completedCount + 1,
        completedNames: [...completedNames, name],
      );
}
