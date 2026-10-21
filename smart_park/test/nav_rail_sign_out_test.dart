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
}
