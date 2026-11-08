import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/widgets/smartpark_ui.dart';

void main() {
  testWidgets('the selected pill slides to the new option', (
    WidgetTester tester,
  ) async {
    String selected = 'Week';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 408, // 4 options of 100 + 2 x 4 padding
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) =>
                  SpSegmentedControl<String>(
                    options: const <(String, String)>[
                      ('Week', 'Week'),
                      ('Month', 'Month'),
                      ('Quarter', 'Quarter'),
                      ('Year', 'Year'),
                    ],
                    selected: selected,
                    onChanged: (String v) => setState(() => selected = v),
                  ),
            ),
          ),
        ),
      ),
    );
    double pillLeft() => tester
        .widget<AnimatedPositioned>(find.byType(AnimatedPositioned))
        .left!;
    double pillX() => tester.getTopLeft(find.byType(AnimatedPositioned)).dx;

    expect(pillLeft(), 0);
    final double start = pillX();

    await tester.tap(find.text('Year'));
    await tester.pump();
    expect(pillLeft(), 300);
    // Partway through, the pill is between the two options...
    await tester.pump(const Duration(milliseconds: 100));
    expect(pillX(), greaterThan(start));
    expect(pillX(), lessThan(start + 300));
    // ...and it settles on the new one.
    await tester.pumpAndSettle();
    expect(pillX(), start + 300);
  });
}
