import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/platform/platform_utils.dart';
import 'core/theme/app_theme.dart';
import 'features/share/share_intent_listener.dart';

class PuggyBankApp extends StatelessWidget {
  const PuggyBankApp({super.key, required this.routerConfig});

  final GoRouter routerConfig;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PuggyBank',
      theme: buildPuggyTheme(),
      routerConfig: routerConfig,
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
