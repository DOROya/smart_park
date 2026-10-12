import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/widgets/smartpark_ui.dart';

void main() {
  Future<void> pumpAt(WidgetTester tester, double width) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: const SpSlotsCard(
                totalSlots: 15,
                occupied: 1,
                carSlots: 10,
                motorcycleSlots: 5,
                carOccupied: 0,
                motorcycleOccupied: 1,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a narrow column stacks the card instead of squeezing it', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, 280); // a small tablet's side column
    expect(tester.takeException(), isNull);
    // The ring sits above the legend, and the type boxes stack.
    final double ringBottom = tester.getBottomLeft(find.text('occupied')).dy;
    expect(
      tester.getTopLeft(find.text('Occupied')).dy,
      greaterThan(ringBottom),
    );
    expect(
      tester.getTopLeft(find.text('Motorcycle')).dy,
      greaterThan(tester.getTopLeft(find.text('Car')).dy),
    );
    // Labels keep their words whole: one line each.
    expect(tester.getSize(find.text('Occupied')).height, lessThan(24));
    expect(tester.getSize(find.text('Total capacity')).height, lessThan(24));
    expect(find.text('Plenty of space'), findsOneWidget);
  });

  testWidgets('a wide card keeps the side-by-side layout', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, 500);
    expect(tester.takeException(), isNull);
    final double ringRight = tester.getTopRight(find.text('occupied')).dx;
    expect(tester.getTopLeft(find.text('Occupied')).dx, greaterThan(ringRight));
    expect(find.text('Car occupied'), findsOneWidget);
    expect(find.text('Motorcycle occupied'), findsOneWidget);
  });
}
