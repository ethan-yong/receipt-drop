import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/payment_detection/payment_event_drain_service.dart';
import 'core/platform/platform_utils.dart';
import 'core/theme/app_theme.dart';
import 'features/share/share_intent_listener.dart';

class ReceiptDropApp extends StatefulWidget {
  const ReceiptDropApp({
    super.key,
    required this.routerConfig,
    this.theme,
  });

  final GoRouter routerConfig;
  final ThemeData? theme;

  @override
  State<ReceiptDropApp> createState() => _ReceiptDropAppState();
}

class _ReceiptDropAppState extends State<ReceiptDropApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The overlay queues category picks natively; if the user returns to an
    // already-running process (warm resume), startup-only draining never ran.
    if (state == AppLifecycleState.resumed) {
      unawaited(PaymentEventDrainService.drainAndIngest());
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Receipt Drop',
      debugShowCheckedModeBanner: false,
      theme: widget.theme ?? buildReceiptDropTheme(),
      routerConfig: widget.routerConfig,
      builder: (context, child) {
        Widget result = ShareIntentListener(
          child: child ?? const SizedBox.shrink(),
        );
        if (PlatformUtils.isCupertino) {
          result = CupertinoTheme(
            data: const CupertinoThemeData(
              primaryColor: AppColors.primaryGreen,
              barBackgroundColor: AppColors.scaffold,
            ),
            child: result,
          );
        }
        return result;
      },
    );
  }
}
