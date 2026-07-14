import '../../features/share/receipt_ingest_draft.dart';

sealed class OcrProgressEvent {
  const OcrProgressEvent();
}

class ReceiptUploadedEvent extends OcrProgressEvent {
  const ReceiptUploadedEvent();
}

class OcrStartedEvent extends OcrProgressEvent {
  const OcrStartedEvent();
}

class OcrCompletedEvent extends OcrProgressEvent {
  const OcrCompletedEvent();
}

class MerchantIdentifiedEvent extends OcrProgressEvent {
  const MerchantIdentifiedEvent({this.merchant});
  final String? merchant;
}

class ItemsExtractedEvent extends OcrProgressEvent {
  const ItemsExtractedEvent({required this.count});
  final int count;
}

class TotalExtractedEvent extends OcrProgressEvent {
  const TotalExtractedEvent({this.amount});
  final double? amount;
}

class CategoryPredictedEvent extends OcrProgressEvent {
  const CategoryPredictedEvent({required this.category});
  final String category;
}

class ProcessingCompletedEvent extends OcrProgressEvent {
  const ProcessingCompletedEvent({required this.draft});
  final ReceiptIngestDraft draft;
}

class ProcessingFailedEvent extends OcrProgressEvent {
  const ProcessingFailedEvent({required this.error});
  final Object error;
}
