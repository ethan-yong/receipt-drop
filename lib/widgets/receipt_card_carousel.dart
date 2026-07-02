import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/theme/app_theme.dart';
import '../domain/models/transaction_view.dart';
import 'receipt_card.dart';

class ReceiptCardCarousel extends StatefulWidget {
  const ReceiptCardCarousel({super.key, required this.transactions});

  final List<TransactionView> transactions;

  @override
  State<ReceiptCardCarousel> createState() => _ReceiptCardCarouselState();
}

class _ReceiptCardCarouselState extends State<ReceiptCardCarousel> {
  late final PageController _controller;
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.88);
    _controller.addListener(() {
      final page = _controller.page?.round() ?? 0;
      if (page != _currentPage) {
        setState(() => _currentPage = page);
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txs = widget.transactions;

    if (txs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: Text(
            'No receipts today yet',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColors.textMuted,
                ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 480,
          child: PageView.builder(
            controller: _controller,
            clipBehavior: Clip.none,
            itemCount: txs.length,
            itemBuilder: (context, i) {
              final tx = txs[i];
              return ReceiptCard(
                tx: tx,
                onTap: () => context.pushNamed(
                  'tx-detail',
                  pathParameters: {'id': tx.id},
                ),
              );
            },
          ),
        ),
        if (txs.length > 1) ...[
          const SizedBox(height: 14),
          _DotIndicator(
            count: txs.length,
            current: _currentPage.clamp(0, txs.length - 1),
            palettes: txs.map((t) => receiptPaletteForCategory(t.effectiveCategory)).toList(),
          ),
        ],
      ],
    );
  }
}

class _DotIndicator extends StatelessWidget {
  const _DotIndicator({
    required this.count,
    required this.current,
    required this.palettes,
  });

  final int count;
  final int current;
  final List<ReceiptCardPalette> palettes;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 20 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: isActive ? palettes[i].acc : AppColors.divider,
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}
