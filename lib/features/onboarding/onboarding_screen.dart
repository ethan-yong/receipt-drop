import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/bootstrap/app_prefs.dart';
import '../../core/theme/app_theme.dart';

/// Three short slides, then routes to sign-in (onboarding in design spec).
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _index = 0;

  static const _slides = <({String title, String body})>[
    (
      title: 'Share any RM receipt',
      body:
          'Use your bank or TNG receipt screenshot — tap Share and choose PuggyBank.',
    ),
    (
      title: 'We guess place & category',
      body:
          'You can fix anything later. Nothing blocks you from saving right away.',
    ),
    (
      title: 'Your data, your map',
      body:
          'Spend rolls up on your dashboard and map. PuggyBank is not a bank.',
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
        duration: const Duration(milliseconds: 300),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.title,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryGreen,
                              ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          s.body,
                          style: Theme.of(context).textTheme.bodyLarge,
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
                (i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: CircleAvatar(
                    radius: 4,
                    backgroundColor: i == _index
                        ? AppColors.primaryGreen
                        : Colors.grey.shade400,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: FilledButton(
                onPressed: () {
                  _next(context);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(
                  _index == _slides.length - 1 ? 'Get started' : 'Next',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
