import 'package:flutter_test/flutter_test.dart';
import 'package:puggy_bank/app.dart';

void main() {
  testWidgets('Home tab loads', (WidgetTester tester) async {
    await tester.pumpWidget(const PuggyBankApp());
    await tester.pumpAndSettle();

    expect(
      find.text('Your spending feed will appear here.'),
      findsOneWidget,
    );
    expect(find.text('Map'), findsOneWidget);
  });
}
