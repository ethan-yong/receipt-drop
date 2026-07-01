import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';
import '../domain/logic/dashboard_aggregates.dart';

class TopPlacesList extends StatelessWidget {
  const TopPlacesList({super.key, required this.places});

  final List<TopPlaceRow> places;

  @override
  Widget build(BuildContext context) {
    if (places.isEmpty) {
      return Text(
        'No places with location yet.',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }

    final currency = NumberFormat.currency(symbol: 'RM ', decimalDigits: 2);

    return Column(
      children: places.map((p) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.displayName,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      '${p.visitCount} visits',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Text(
                currency.format(p.totalSpend),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppColors.primaryGreen,
                    ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
