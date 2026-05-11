import 'package:flutter/material.dart';

/// Placeholder — wired in router for Task 12.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Onboarding')),
      body: const Center(child: Text('Onboarding slides — coming soon.')),
    );
  }
}
