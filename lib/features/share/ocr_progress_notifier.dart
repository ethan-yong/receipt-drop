import 'dart:async';

import '../../domain/models/ocr_progress_event.dart';

enum OcrProcessingStage {
  uploading,
  scanning,
  extracting,
  merchant,
  items,
  total,
  category,
  done,
}

/// Wraps a broadcast [StreamController] and enforces a minimum display time
/// per log step so no event is invisible even when the pipeline runs fast.
class OcrProgressNotifier {
  OcrProgressNotifier() : _ctrl = StreamController<OcrProgressEvent>.broadcast();

  static const _kMinStepMs = 350;

  final StreamController<OcrProgressEvent> _ctrl;
  DateTime? _lastLogStep;

  Stream<OcrProgressEvent> get stream => _ctrl.stream;

  /// Emits [event] on the stream, waiting if needed so every log-step event is
  /// displayed for at least [_kMinStepMs] milliseconds before the next one.
  Future<void> emit(OcrProgressEvent event) async {
    if (_isLogStep(event)) {
      final last = _lastLogStep;
      if (last != null) {
        final elapsed = DateTime.now().difference(last).inMilliseconds;
        if (elapsed < _kMinStepMs) {
          await Future<void>.delayed(
            Duration(milliseconds: _kMinStepMs - elapsed),
          );
        }
      }
      _lastLogStep = DateTime.now();
    }
    if (!_ctrl.isClosed) _ctrl.add(event);
  }

  void dispose() => _ctrl.close();

  static bool _isLogStep(OcrProgressEvent event) => switch (event) {
        OcrStartedEvent() => true,
        MerchantIdentifiedEvent() => true,
        TotalExtractedEvent() => true,
        CategoryPredictedEvent() => true,
        ProcessingCompletedEvent() => true,
        _ => false,
      };
}
