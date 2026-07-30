import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_drop/core/theme/app_theme.dart';
import 'package:receipt_drop/domain/logic/insight_visualization.dart';
import 'package:receipt_drop/widgets/insight_visualization.dart';

void main() {
  group('insightVisualKind', () {
    test('maps each known visualization type', () {
      expect(
        insightVisualKind({'type': 'line_trend'}),
        InsightVisualKind.lineTrend,
      );
      expect(
        insightVisualKind({'type': 'before_after_bar'}),
        InsightVisualKind.beforeAfterBar,
      );
      expect(
        insightVisualKind({'type': 'habit_timeline'}),
        InsightVisualKind.habitTimeline,
      );
      expect(
        insightVisualKind({'type': 'forecast_projection'}),
        InsightVisualKind.forecastProjection,
      );
    });

    test('returns null for null input', () {
      expect(insightVisualKind(null), isNull);
    });

    test('returns null for location_heatmap (allowed on the wire, no widget yet)', () {
      expect(insightVisualKind({'type': 'location_heatmap'}), isNull);
    });

    test('returns null for an unknown type', () {
      expect(insightVisualKind({'type': 'pie_of_doom'}), isNull);
    });
  });

  group('InsightVisualization widget', () {
    Future<void> pump(WidgetTester tester, Map<String, dynamic>? viz) {
      return tester.pumpWidget(
        MaterialApp(
          theme: buildReceiptDropTestTheme(),
          home: Scaffold(
            body: InsightVisualization(visualization: viz),
          ),
        ),
      );
    }

    testWidgets('renders nothing for null visualization', (tester) async {
      await pump(tester, null);
      expect(find.byType(LineChart), findsNothing);
      expect(find.byType(BarChart), findsNothing);
    });

    testWidgets('renders nothing for an unsupported type', (tester) async {
      await pump(tester, {'type': 'location_heatmap', 'parameters': {}});
      expect(find.byType(LineChart), findsNothing);
      expect(find.byType(BarChart), findsNothing);
    });

    testWidgets('renders nothing when a required parameter is missing',
        (tester) async {
      await pump(tester, {
        'type': 'before_after_bar',
        'parameters': {'category': 'Food', 'previous': 110.0},
        // 'current' missing — must not fabricate a bar.
      });
      expect(find.byType(BarChart), findsNothing);
    });

    testWidgets('renders a line chart for line_trend', (tester) async {
      await pump(tester, {
        'type': 'line_trend',
        'parameters': {
          'weekday': 'Tuesday',
          'baseline': 20.0,
          'today_total': 80.0,
        },
        'animation': {'type': 'line_draw', 'duration_ms': 100},
      });
      await tester.pumpAndSettle();
      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets('renders a bar chart for before_after_bar', (tester) async {
      await pump(tester, {
        'type': 'before_after_bar',
        'parameters': {
          'category': 'Food',
          'previous': 110.0,
          'current': 150.0,
        },
        'animation': {'type': 'bars_grow', 'duration_ms': 100},
      });
      await tester.pumpAndSettle();
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.text('Food'), findsOneWidget);
    });

    testWidgets('renders icons for habit_timeline', (tester) async {
      await pump(tester, {
        'type': 'habit_timeline',
        'parameters': {
          'place_name': 'Tealive',
          'visits': 3,
          'window_days': 7,
        },
        'animation': {'type': 'icons_pop', 'duration_ms': 90},
      });
      await tester.pumpAndSettle();
      expect(find.byType(CircleAvatar), findsNWidgets(3));
      expect(find.textContaining('Tealive'), findsOneWidget);
    });

    testWidgets('renders a line chart for forecast_projection', (tester) async {
      await pump(tester, {
        'type': 'forecast_projection',
        'parameters': {
          'prior_month': 400.0,
          'current_so_far': 300.0,
          'projected': 500.0,
        },
        'animation': {'type': 'forecast_reveal', 'duration_ms': 100},
      });
      await tester.pumpAndSettle();
      expect(find.byType(LineChart), findsOneWidget);
    });
  });
}
