import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../core/platform/platform_utils.dart';

/// Pull-to-refresh with iOS bounce vs Android clamp physics.
class PlatformRefreshScrollView extends StatelessWidget {
  const PlatformRefreshScrollView({
    super.key,
    required this.onRefresh,
    required this.slivers,
  });

  final Future<void> Function() onRefresh;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    final scrollView = CustomScrollView(
      physics: PlatformUtils.listPhysics(context),
      slivers: [
        if (PlatformUtils.isCupertino)
          CupertinoSliverRefreshControl(onRefresh: onRefresh),
        ...slivers,
      ],
    );

    if (PlatformUtils.isCupertino) return scrollView;

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: Theme.of(context).colorScheme.primary,
      child: scrollView,
    );
  }
}
