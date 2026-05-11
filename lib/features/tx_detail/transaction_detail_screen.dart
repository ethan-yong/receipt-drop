import 'package:flutter/material.dart';

/// Placeholder — Task 15.
class TransactionDetailScreen extends StatelessWidget {
  const TransactionDetailScreen({super.key, required this.transactionId});

  final String transactionId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transaction')),
      body: Center(child: Text('Transaction $transactionId — coming soon.')),
    );
  }
}
