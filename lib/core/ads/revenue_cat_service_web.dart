/// No ad SDK runs on web (see [AdsService]) — nothing to configure.
abstract final class RevenueCatService {
  static Future<void> init() async {}
}
