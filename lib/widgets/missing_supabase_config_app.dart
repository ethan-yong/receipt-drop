import 'package:flutter/material.dart';

/// Shown when neither dart-define nor `.env` provides Supabase credentials.
class MissingSupabaseConfigApp extends StatelessWidget {
  const MissingSupabaseConfigApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Receipt Drop',
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Text(
                  'Missing Supabase configuration.\n\n'
                  'Set SUPABASE_URL and SUPABASE_ANON_KEY using '
                  '--dart-define when running flutter run, '
                  'or add a .env file in the project root for debug builds '
                  '(see .env.example).',
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
