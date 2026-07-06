import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/social_repository.dart';
import '../../widgets/settings_tile.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _version = '1.0.0';

  // Optimistic default (matches the server column default) while loading.
  bool _shareMapLocation = true;

  @override
  void initState() {
    super.initState();
    SocialRepository.getShareMapLocation().then((value) {
      if (mounted) setState(() => _shareMapLocation = value);
    });
  }

  void _setShareMapLocation(bool value) {
    setState(() => _shareMapLocation = value);
    SocialRepository.setShareMapLocation(value);
  }

  Future<void> _signOut() async {
    if (!Env.hasSupabaseConfig) return;
    try {
      await Supabase.instance.client.auth.signOut();
    } on Object {
      // No session in debug/skip-auth flows.
    }
  }

  Future<void> _clearCache() async {
    await AppServices.transactions.clearAll();
    await AppServices.transactions.seedDemoDataIfEmpty();
    if (kDebugMode) {
      await AppServices.transactions.seedReceiptShowcaseIfEmpty();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Local cache cleared (cloud data kept)')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SettingsTile(
            icon: Icons.person_outline,
            title: 'Account',
            subtitle: Env.hasSupabaseConfig
                ? Supabase.instance.client.auth.currentUser?.email
                : 'Demo mode',
            onTap: () {},
          ),
          SettingsTile(
            icon: Icons.logout,
            title: 'Sign out',
            destructive: true,
            onTap: _signOut,
          ),
          const Divider(),
          SettingsTile(
            icon: Icons.download_outlined,
            title: 'Export (CSV)',
            subtitle: 'Coming in v1.1',
            onTap: () {},
          ),
          SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy & Legal',
            onTap: () {},
          ),
          SwitchListTile(
            secondary: const Icon(
              Icons.location_on_outlined,
              color: AppColors.textPrimary,
            ),
            title: Text(
              "Show me on friends' maps",
              style: Theme.of(context).textTheme.titleSmall,
            ),
            subtitle: Text(
              'Your latest receipt place appears as a pin',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            value: _shareMapLocation,
            activeTrackColor: AppColors.primaryGreen,
            onChanged: _setShareMapLocation,
          ),
          SettingsTile(
            icon: Icons.cleaning_services_outlined,
            title: 'Clear local cache',
            subtitle: 'Does not delete cloud data',
            onTap: _clearCache,
          ),
          SettingsTile(
            icon: Icons.people_outline,
            title: 'Friends',
            onTap: () => context.pushNamed('friends'),
          ),
          SettingsTile(
            icon: Icons.dashboard_outlined,
            title: 'Dashboard',
            subtitle: 'Full numbers, charts, and receipt history',
            onTap: () => context.pushNamed('dashboard'),
          ),
          SettingsTile(
            icon: Icons.info_outline,
            title: 'App version',
            trailing: Text(_version, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
