import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/core/theme/app_theme.dart';
import 'package:receipt_drop/domain/models/insight_candidate.dart';
import 'package:receipt_drop/widgets/insight_home_card.dart';

void main() {
  test('insightTypeIcon maps each closed type', () {
    expect(insightTypeIcon('spending_spike'), Icons.trending_up_rounded);
    expect(insightTypeIcon('category_shift'), Icons.pie_chart_outline_rounded);
    expect(insightTypeIcon('habit'), Icons.place_outlined);
    expect(insightTypeIcon('streak'), Icons.local_fire_department_outlined);
    expect(insightTypeIcon('forecast'), Icons.timeline_rounded);
  });

  testWidgets('dismissible insight row removes on close tap', (tester) async {
    final dismissed = <String>[];
    final insight = CuratedInsight(
      id: 'i1',
      type: 'streak',
      factKey: 'streak:3:2026-07-28',
      body: 'You logged receipts 3 days in a row',
      rank: 0,
      createdAt: DateTime(2026, 7, 28),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildReceiptDropTestTheme(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              if (dismissed.contains(insight.id)) {
                return const Text('gone');
              }
              return ListTile(
                title: Text(insight.body),
                trailing: IconButton(
                  key: const Key('dismiss'),
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() => dismissed.add(insight.id)),
                ),
              );
            },
          ),
        ),
      ),
    );

    expect(find.text(insight.body), findsOneWidget);
    await tester.tap(find.byKey(const Key('dismiss')));
    await tester.pumpAndSettle();
    expect(find.text('gone'), findsOneWidget);
    expect(dismissed, ['i1']);
  });
}
