/// `google_mobile_ads` has no web implementation — every call is a no-op.
abstract final class AdsService {
  static Future<void> init() async {}
}
