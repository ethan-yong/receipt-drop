import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../data/repositories/places_repository.dart';

class PlacesSearchScreen extends StatefulWidget {
  const PlacesSearchScreen({super.key});

  @override
  State<PlacesSearchScreen> createState() => _PlacesSearchScreenState();
}

class _PlacesSearchScreenState extends State<PlacesSearchScreen> {
  final _queryController = TextEditingController();
  Timer? _debounce;
  List<PlaceResult> _results = const [];
  var _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(value));
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      if (mounted) setState(() => _results = const []);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final results = await PlacesRepository.search(query);
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
      if (results.isEmpty && query.trim().length >= 2) {
        _error = 'No places found. Try a different search.';
      }
    });
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
              onChanged: _onQueryChanged,
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(_error!, style: Theme.of(context).textTheme.bodySmall),
            ),
          Expanded(
            child: ListView(
              children: [
                for (final r in _results)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          AppColors.primaryGreen.withValues(alpha: 0.12),
                      child: const Icon(
                        Icons.storefront_outlined,
                        color: AppColors.primaryGreen,
                      ),
                    ),
                    title: Text(r.name),
                    subtitle: Text(r.address),
                    onTap: () => context.pop(r),
                  ),
                if (_results.isEmpty && !_loading && _queryController.text.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      'Search for a shop, mall, or restaurant in Malaysia.',
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
