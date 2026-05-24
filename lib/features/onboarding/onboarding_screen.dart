import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/bootstrap/app_prefs.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/pug_mascot.dart';
import '../../widgets/puggy_primary_button.dart';

/// Three slides matching design mock, then routes to sign-in.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _index = 0;

  static const _slides = <({String asset, String title, String body})>[
    (
      asset: 'assets/branding/pug-onboarding-1.png',
      title: 'Share any RM receipt',
      body: 'We log it. Use your bank or TNG receipt — tap Share and choose PuggyBank.',
    ),
    (
      asset: 'assets/branding/pug-onboarding-2.png',
      title: 'We guess place + category',
      body: 'You can fix anything later. Nothing blocks you from saving right away.',
    ),
    (
      asset: 'assets/branding/pug-onboarding-3.png',
      title: 'Your data, your map',
      body: 'Private. Secure. Yours. PuggyBank is not a bank.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finishAndGoAuth(BuildContext context) async {
    await AppPrefs.setOnboardingComplete();
    if (context.mounted) context.go('/auth');
  }

  Future<void> _next(BuildContext context) async {
    if (_index < _slides.length - 1) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      await _finishAndGoAuth(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _finishAndGoAuth(context),
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  final s = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TweenAnimationBuilder<double>(
                          key: ValueKey(i),
                          tween: Tween(begin: 0.85, end: 1),
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                          builder: (context, scale, child) {
                            return Transform.scale(scale: scale, child: child);
                          },
                          child: PugMascot(assetPath: s.asset, size: 160),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          s.title,
                          style: Theme.of(context).textTheme.headlineMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          s.body,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: AppColors.textSecondary,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _slides.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _index ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _index
                        ? AppColors.primaryGreen
                        : Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: PuggyPrimaryButton(
                label: _index == _slides.length - 1
                    ? "Let's get started"
                    : 'Next',
                onPressed: () => _next(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
