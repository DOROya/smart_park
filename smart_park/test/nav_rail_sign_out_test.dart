import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/widgets/smartpark_ui.dart';

void main() {
  for (final bool extended in <bool>[false, true]) {
    testWidgets(
      'sign out sits at the bottom of the ${extended ? 'extended' : 'compact'} rail',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(2048, 1536);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        int signOuts = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SpRailLayout(
                rail: SpNavRail(
                  items: const <(IconData, IconData, String)>[
                    (Icons.home_outlined, Icons.home_rounded, 'Home'),
                    (Icons.person_outline, Icons.person_rounded, 'Profile'),
                  ],
                  selectedIndex: 0,
                  onSelected: (_) {},
                  extended: extended,
                  onSignOut: () => signOuts++,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final double screenBottom = tester.view.physicalSize.height / 2;
        final double signOutBottom = tester
            .getBottomLeft(find.text('Sign Out'))
            .dy;
        expect(signOutBottom, greaterThan(screenBottom - 80));
        expect(
          signOutBottom,
          greaterThan(tester.getBottomLeft(find.text('Profile')).dy),
        );

        await tester.tap(find.text('Sign Out'));
        expect(signOuts, 1);
      },
    );
  }

  testWidgets('tablet content stops above the system taskbar', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(2304, 1440);
    tester.view.devicePixelRatio = 2;
    tester.view.viewPadding = const FakeViewPadding(bottom: 96);
    tester.view.padding = const FakeViewPadding(bottom: 96);
    addTearDown(tester.view.reset);
    const Key content = Key('content');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SpRailLayout(
            rail: SpNavRail(
              items: const <(IconData, IconData, String)>[
                (Icons.home_outlined, Icons.home_rounded, 'Home'),
                (Icons.person_outline, Icons.person_rounded, 'Profile'),
              ],
              selectedIndex: 0,
              onSelected: (_) {},
            ),
            child: const SizedBox.expand(key: content),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.getBottomLeft(find.byKey(content)).dy, 720 - 48);
  });

  group('sign out confirmation', () {
    Future<bool?> ask(
      WidgetTester tester,
      Future<void> Function() answer,
    ) async {
      bool? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) => TextButton(
              onPressed: () async => result = await spConfirmSignOut(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(result, isNull);
      await answer();
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('signs out only when confirmed', (WidgetTester tester) async {
      expect(
        await ask(tester, () => tester.tap(find.text('Sign Out'))),
        isTrue,
      );
    });

    testWidgets('Cancel keeps the session', (WidgetTester tester) async {
      expect(await ask(tester, () => tester.tap(find.text('Cancel'))), isFalse);
    });

    testWidgets('tapping outside keeps the session', (
      WidgetTester tester,
    ) async {
      expect(
        await ask(tester, () => tester.tapAt(const Offset(5, 5))),
        isFalse,
      );
    });
  });
}
