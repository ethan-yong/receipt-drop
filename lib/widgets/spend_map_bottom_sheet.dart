import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';
import '../domain/logic/dashboard_aggregates.dart';
import 'transaction_list_tile.dart';

class SpendMapBottomSheet extends StatelessWidget {
  const SpendMapBottomSheet({
    super.key,
    required this.cluster,
  });

  final MapPlaceCluster cluster;

  static Future<void> show(BuildContext context, MapPlaceCluster cluster) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.45,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        builder: (_, scrollController) {
          return SpendMapBottomSheet(cluster: cluster);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: 'RM ', decimalDigits: 2);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cluster.displayName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${fmt.format(cluster.totalSpend)} · ${cluster.visitCount} visits',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: cluster.transactions.length,
            itemBuilder: (context, i) {
              final tx = cluster.transactions[i];
              return TransactionListTile(
                transaction: tx,
                onTap: () {
                  Navigator.pop(context);
                  context.pushNamed(
                    'tx-detail',
                    pathParameters: {'id': tx.id},
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
