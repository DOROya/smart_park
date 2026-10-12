import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/screens/driver/driver_package_selection_page.dart';

void main() {
  const List<DriverPackageOption> options = <DriverPackageOption>[
    DriverPackageOption(
      key: 'base',
      label: 'Base Package',
      icon: Icons.timer_outlined,
      initialAmount: 50,
    ),
    DriverPackageOption(
      key: 'weekly',
      label: 'Weekly Package',
      icon: Icons.date_range_outlined,
      initialAmount: 0,
      weeklyAmount: 1200,
    ),
    DriverPackageOption(
      key: 'monthly',
      label: 'Monthly Package',
      icon: Icons.calendar_month_outlined,
      initialAmount: 0,
      monthlyAmount: 4000,
    ),
  ];

  /// Opens the picker from a button so the page's pop result is captured.
  Future<DriverPackageSelection? Function()> openPicker(
    WidgetTester tester, {
    Size physicalSize = const Size(1080, 2400),
    double devicePixelRatio = 2.5,
  }) async {
    DriverPackageSelection? result;
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = devicePixelRatio;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => ElevatedButton(
            onPressed: () async {
              result = await Navigator.of(context).push(
                MaterialPageRoute<DriverPackageSelection>(
                  builder: (_) => const DriverPackageSelectionPage(
                    establishmentName: 'Lot 1',
                    vehicleLabel: 'Car',
                    options: options,
                  ),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return () => result;
  }

  testWidgets('weekly package: pick 2 weeks and return the right price', (
    WidgetTester tester,
  ) async {
    final DriverPackageSelection? Function() result = await openPicker(tester);

    expect(find.text('Weekly Package'), findsOneWidget);
    expect(find.text('/ week'), findsOneWidget);
    expect(find.text('Monthly Package'), findsOneWidget);
    expect(find.text('/ month'), findsOneWidget);

    await tester.tap(find.text('Weekly Package'));
    await tester.pumpAndSettle();
    expect(find.text('Number of weeks'), findsOneWidget);
    expect(find.text('Up to 4 weeks.'), findsOneWidget);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('2 weeks × ₱1200'), findsOneWidget);
    expect(find.text('₱2400'), findsWidgets);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    final DriverPackageSelection selection = result()!;
    expect(selection.plan, 'weekly');
    expect(selection.duration, 2);
    expect(selection.unitAmount, 1200);
    expect(selection.totalAmount, 2400);
    expect(selection.displayDurationLabel, '2 weeks');
  });

  testWidgets('monthly package stops at 3 months', (WidgetTester tester) async {
    final DriverPackageSelection? Function() result = await openPicker(tester);

    await tester.tap(find.text('Monthly Package'));
    await tester.pumpAndSettle();
    for (int i = 0; i < 5; i++) {
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Maximum of 3 months.'), findsOneWidget);
    expect(find.text('₱12000'), findsWidgets);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(result()!.plan, 'monthly');
    expect(result()!.duration, 3);
    expect(result()!.totalAmount, 12000);
  });

  testWidgets('works on a landscape tablet (1280x800)', (
    WidgetTester tester,
  ) async {
    final DriverPackageSelection? Function() result = await openPicker(
      tester,
      physicalSize: const Size(2560, 1600),
      devicePixelRatio: 2,
    );
    await tester.tap(find.text('Weekly Package'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('2 weeks × ₱1200'), findsOneWidget);
    // The content column stays readable instead of stretching edge to edge.
    expect(tester.getSize(find.text('Weekly Package')).width, lessThan(640));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(result()!.totalAmount, 2400);
  });
}
