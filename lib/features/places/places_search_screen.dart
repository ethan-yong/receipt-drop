import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

class PlacesSearchScreen extends StatefulWidget {
  const PlacesSearchScreen({super.key});

  @override
  State<PlacesSearchScreen> createState() => _PlacesSearchScreenState();
}

class _PlacesSearchScreenState extends State<PlacesSearchScreen> {
  final _queryController = TextEditingController();
  final _demoResults = const [
    ('7-Eleven Sunway', 'Jalan PJS 11/15, Bandar Sunway'),
    ('Tealive SS15', 'Jalan SS 15/4, Subang Jaya'),
    ('Village Grocer', '1 Utama Shopping Centre'),
    ('AEON Big', 'Mid Valley Megamall'),
  ];

  List<(String, String)> get _filtered {
    final q = _queryController.text.trim().toLowerCase();
    if (q.isEmpty) return _demoResults;
    return _demoResults
        .where(
          (r) =>
              r.$1.toLowerCase().contains(q) ||
              r.$2.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Change place'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              controller: _queryController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search places',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                for (final r in _filtered)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          AppColors.primaryGreen.withValues(alpha: 0.12),
                      child: const Icon(
                        Icons.storefront_outlined,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                    title: Text(r.$1),
                    subtitle: Text(r.$2),
                    onTap: () => context.pop(r.$1),
                  ),
                ListTile(
                  leading: const Icon(Icons.pin_drop_outlined),
                  title: const Text('Choose on map'),
                  subtitle: const Text('Drop a pin manually'),
                  onTap: () => context.pop('Custom location'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
