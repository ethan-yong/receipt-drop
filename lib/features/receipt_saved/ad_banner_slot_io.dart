import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:uuid/uuid.dart';

import '../../core/ads/ad_revenue_tracker.dart';
import '../../core/config/ads_config.dart';

/// Reserved AdMob banner slot below the receipt summary card. Android only
/// (Stage 1) — every other platform renders nothing.
///
/// Reserves [_reservedHeight] from the first frame regardless of load
/// state, so the screen never jumps when the ad resolves; collapses to
/// nothing only if the ad fails to load.
class AdBannerSlot extends StatefulWidget {
  const AdBannerSlot({super.key});

  @override
  State<AdBannerSlot> createState() => _AdBannerSlotState();
}

class _AdBannerSlotState extends State<AdBannerSlot> {
  static const _reservedHeight = 52.0;

  BannerAd? _bannerAd;
  bool _loaded = false;
  bool _failed = false;

  // Generated once per ad instance and reused across every RevenueCat
  // tracking call for it, so rebuilds (which never call _loadAd again)
  // can't produce duplicate/mismatched tracking events.
  late final String _impressionId;

  bool get _supported => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    if (_supported) _loadAd();
  }

  void _loadAd() {
    _impressionId = const Uuid().v4();
    final ad = BannerAd(
      adUnitId: AdsConfig.androidBannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          unawaited(
            AdRevenueTracker.trackLoaded(
              impressionId: _impressionId,
              adUnitId: AdsConfig.androidBannerAdUnitId,
            ),
          );
          if (!mounted) return;
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          unawaited(
            AdRevenueTracker.trackFailedToLoad(
              impressionId: _impressionId,
              adUnitId: AdsConfig.androidBannerAdUnitId,
              errorCode: error.code,
            ),
          );
          ad.dispose();
          if (!mounted) return;
          setState(() => _failed = true);
        },
        onAdImpression: (_) {
          unawaited(
            AdRevenueTracker.trackDisplayed(
              impressionId: _impressionId,
              adUnitId: AdsConfig.androidBannerAdUnitId,
            ),
          );
        },
        onPaidEvent: (ad, valueMicros, precision, currencyCode) {
          unawaited(
            AdRevenueTracker.trackRevenue(
              impressionId: _impressionId,
              adUnitId: AdsConfig.androidBannerAdUnitId,
              valueMicros: valueMicros,
              precision: precision,
              currencyCode: currencyCode,
            ),
          );
        },
      ),
    );
    _bannerAd = ad;
    ad.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported || _failed) return const SizedBox.shrink();

    final ad = _bannerAd;
    return SizedBox(
      height: _reservedHeight,
      width: double.infinity,
      child: (_loaded && ad != null)
          ? Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: ad.size.width.toDouble(),
                  height: ad.size.height.toDouble(),
                  child: AdWidget(ad: ad),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
