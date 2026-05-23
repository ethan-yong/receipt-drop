import 'dart:async';

import '../../domain/models/transaction_view.dart';
import 'demo_transactions.dart';

/// In-memory transactions for Flutter Web (Drift/SQLite uses dart:ffi on native only).
class TransactionRepository {
  TransactionRepository();

  final _rows = <TransactionView>[];
  final _controller = StreamController<List<TransactionView>>.broadcast();

  Stream<List<TransactionView>> watchAll() {
  Future.microtask(_emit);
    return _controller.stream;
  }

  Future<TransactionView?> getById(String id) async {
    for (final row in _rows) {
      if (row.id == id) return row;
    }
    return null;
  }

  Future<void> updateTransaction(TransactionView view) async {
    final i = _rows.indexWhere((r) => r.id == view.id);
    if (i >= 0) {
      _rows[i] = view;
      _emit();
    }
  }

  Future<void> deleteTransaction(String id) async {
    _rows.removeWhere((r) => r.id == id);
    _emit();
  }

  Future<void> clearAll() async {
    _rows.clear();
    _emit();
  }

  Future<int> countAll() async => _rows.length;

  Future<void> seedDemoDataIfEmpty({String userId = 'demo-user'}) async {
    if (_rows.isNotEmpty) return;
    _rows.addAll(demoTransactions(userId: userId));
    _emit();
  }

  void _emit() {
    final sorted = [..._rows]
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    if (!_controller.isClosed) {
      _controller.add(sorted);
    }
  }

  Future<void> dispose() async {
    await _controller.close();
  }
}
