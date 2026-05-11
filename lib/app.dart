import 'package:flutter/material.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

class PuggyBankApp extends StatelessWidget {
  const PuggyBankApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PuggyBank',
      theme: buildPuggyTheme(),
      routerConfig: goRouter,
    );
  }
}
