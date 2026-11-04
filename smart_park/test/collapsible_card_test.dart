import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/widgets/smartpark_ui.dart';

void main() {
  Future<void> pump(WidgetTester tester, {double width = 400}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: const SpCollapsibleCard(
                icon: Icons.storefront_outlined,
                title: 'Facility Details',
                summary: 'Open 24 hours · 20-minute grace period',
                child: Text('Car Rate'),
              ),
            ),
          ),
        ),
      );

  testWidgets('starts closed with just the title and summary', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    expect(find.text('Facility Details'), findsOneWidget);
    expect(find.text('Open 24 hours · 20-minute grace period'), findsOneWidget);
    expect(find.text('Car Rate'), findsNothing);
  });

  testWidgets('tapping the header opens it, tapping again closes it', (
    WidgetTester tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Facility Details'));
    await tester.pumpAndSettle();
    expect(find.text('Car Rate'), findsOneWidget);
    expect(find.textContaining('grace period'), findsNothing);

    await tester.tap(find.text('Facility Details'));
    await tester.pumpAndSettle();
    expect(find.text('Car Rate'), findsNothing);
    expect(find.textContaining('grace period'), findsOneWidget);
  });

  testWidgets('a long summary does not overflow a narrow card', (
    WidgetTester tester,
  ) async {
    await pump(tester, width: 180);

    expect(tester.takeException(), isNull);
  });
}
