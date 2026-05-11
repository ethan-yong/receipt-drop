import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/app_theme.dart';

class PuggyBankApp extends StatelessWidget {
  const PuggyBankApp({super.key, required this.routerConfig});

  final GoRouter routerConfig;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PuggyBank',
      theme: buildPuggyTheme(),
      routerConfig: routerConfig,
    );
  }
}
