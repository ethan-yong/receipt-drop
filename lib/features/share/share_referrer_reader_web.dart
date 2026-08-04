/// Web never receives OS share intents (see `share_intent_listener.dart`),
/// so there's never a referrer to read.
abstract final class ShareReferrerReader {
  static Future<String?> readReferrerPackage() async => null;
}
