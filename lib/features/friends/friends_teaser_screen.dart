import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/pug_mascot.dart';
import '../../widgets/puggy_primary_button.dart';

class FriendsTeaserScreen extends StatefulWidget {
  const FriendsTeaserScreen({super.key});

  @override
  State<FriendsTeaserScreen> createState() => _FriendsTeaserScreenState();
}

class _FriendsTeaserScreenState extends State<FriendsTeaserScreen> {
  var _notified = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Friends'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: PugMascot(size: 80)),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Save together, soon.',
              style: Theme.of(context).textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            _PreviewTile(
              icon: Icons.map_outlined,
              title: 'Friends on your map',
              body: 'See where friends spend — anonymized, opt-in only.',
            ),
            _PreviewTile(
              icon: Icons.place_outlined,
              title: 'Location frequency',
              body: 'Nathan spent here 5 times this week (counts only).',
            ),
            _PreviewTile(
              icon: Icons.flag_outlined,
              title: 'Shared goals',
              body: 'Nathan is 50% through a challenge — week 5 of 10.',
            ),
            const SizedBox(height: AppSpacing.xl),
            PuggyPrimaryButton(
              label: _notified
                  ? "You're on the list"
                  : 'Notify me when this launches',
              onPressed: _notified
                  ? null
                  : () {
                      setState(() => _notified = true);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('We\'ll let you know when Friends ships.'),
                        ),
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewTile extends StatelessWidget {
  const _PreviewTile({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Icon(icon, color: AppColors.primaryGreen),
        title: Text(title, style: Theme.of(context).textTheme.titleSmall),
        subtitle: Text(body),
      ),
    );
  }
}
