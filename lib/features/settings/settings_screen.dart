import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/bootstrap/app_services.dart';
import '../../core/config/env.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/settings_tile.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _version = '1.0.0';

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
