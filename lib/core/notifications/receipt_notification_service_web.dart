/// Web never receives OS share intents and has no OS notification surface
/// for this flow — every call is a no-op.
abstract final class ReceiptNotificationService {
  static Future<void> init() async {}

  static Future<void> showReceiptSaved({
    required String pendingImportId,
    String? sourceApp,
  }) async {}

  static Future<void> showBatchSaved({required int count}) async {}
}
