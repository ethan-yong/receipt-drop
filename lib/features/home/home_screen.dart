import 'package:flutter/material.dart';

/// Main transaction feed (placeholder for Task 15).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: const Center(
        child: Text('Your spending feed will appear here.'),
      ),
    );
  }
}
