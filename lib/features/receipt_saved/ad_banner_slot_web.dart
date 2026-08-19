import 'package:flutter/widgets.dart';

/// `google_mobile_ads` has no web implementation — nothing to reserve or show.
class AdBannerSlot extends StatelessWidget {
  const AdBannerSlot({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
