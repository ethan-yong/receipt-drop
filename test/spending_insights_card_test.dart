import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/core/theme/app_theme.dart';
import 'package:receipt_drop/domain/models/insight_candidate.dart';
import 'package:receipt_drop/widgets/spending_insights_card.dart';

void main() {
  test('insightTypeIcon maps each closed type', () {
    expect(insightTypeIcon('spending_spike'), Icons.trending_up_rounded);
    expect(insightTypeIcon('category_shift'), Icons.pie_chart_outline_rounded);
    expect(insightTypeIcon('habit'), Icons.place_outlined);
    expect(insightTypeIcon('streak'), Icons.local_fire_department_outlined);
    expect(insightTypeIcon('forecast'), Icons.timeline_rounded);
  });

  test('insightHeadlineEmoji maps each closed type', () {
    expect(insightHeadlineEmoji('spending_spike'), '📈');
    expect(insightHeadlineEmoji('category_shift'), '🔄');
    expect(insightHeadlineEmoji('habit'), '☕');
    expect(insightHeadlineEmoji('streak'), '🔥');
    expect(insightHeadlineEmoji('forecast'), '📊');
    expect(insightHeadlineEmoji('unknown'), '✨');
  });

  group('splitInsightBody', () {
    test('splits title. description join from curator', () {
      final split = splitInsightBody(
        'Your cafe visits are becoming a habit. You visited cafes 4 times this week.',
      );
      expect(split.headline, 'Your cafe visits are becoming a habit');
      expect(split.supporting, 'You visited cafes 4 times this week.');
    });

    test('returns headline-only when no title boundary', () {
      final split = splitInsightBody(
        "You've logged receipts 3 days in a row",
      );
      expect(split.headline, "You've logged receipts 3 days in a row");
      expect(split.supporting, isNull);
    });

    test('does not split when first period is past 60 chars', () {
      final long =
          '${'A' * 61}. Rest of the sentence that should stay attached';
      final split = splitInsightBody(long);
      expect(split.supporting, isNull);
      expect(split.headline, long);
    });
  });

  group('insightFreshnessLabel', () {
    final now = DateTime(2026, 7, 29, 12);

    test('today', () {
      expect(
        insightFreshnessLabel(DateTime(2026, 7, 29, 8), now: now),
        'Updated today',
      );
    });

    test('yesterday', () {
      expect(
        insightFreshnessLabel(DateTime(2026, 7, 28), now: now),
        'Updated yesterday',
      );
    });

    test('within a week', () {
      expect(
        insightFreshnessLabel(DateTime(2026, 7, 26), now: now),
        'Updated 3 days ago',
      );
    });

    test('older than a week falls back', () {
      expect(
        insightFreshnessLabel(DateTime(2026, 7, 1), now: now),
        'Based on your recent receipts',
      );
    });
  });

  testWidgets('active state shows headline, supporting, CTA and taps',
      (tester) async {
    var tapped = false;
    final insight = CuratedInsight(
      id: 'i1',
      type: 'habit',
      factKey: 'habit:cafe:2026-07-28',
      body:
          'Your cafe visits are becoming a habit. You visited cafes 4 times this week.',
      rank: 0,
      createdAt: DateTime(2026, 7, 28),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildReceiptDropTestTheme(),
        home: Scaffold(
          body: SpendingInsightsCardView(
            insight: insight,
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('✨ What We Noticed'), findsOneWidget);
    expect(find.text('Your cafe visits are becoming a habit ☕'), findsOneWidget);
    expect(
      find.text('You visited cafes 4 times this week.'),
      findsOneWidget,
    );
    expect(find.text('View insights'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);

    await tester.tap(find.text('View insights'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('empty state is visible, non-tappable, and has no CTA',
      (tester) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildReceiptDropTestTheme(),
        home: Scaffold(
          body: SpendingInsightsCardView(
            // onTap omitted → non-interactive empty card
            insight: null,
            onTap: null,
          ),
        ),
      ),
    );

    expect(find.text('✨ What We Noticed'), findsOneWidget);
    expect(
      find.text(SpendingInsightsCardView.emptyHeadline),
      findsOneWidget,
    );
    expect(
      find.text(SpendingInsightsCardView.emptySupporting),
      findsOneWidget,
    );
    expect(find.text('View insights'), findsNothing);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(GestureDetector), findsNothing);

    // Tapping the headline must not fire anything (no InkWell wired).
    await tester.tap(find.text(SpendingInsightsCardView.emptyHeadline));
    await tester.pump();
    expect(tapped, isFalse);
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
