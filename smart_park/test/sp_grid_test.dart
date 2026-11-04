import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/widgets/smartpark_ui.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required bool equalHeight}) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SpGrid(
                equalHeight: equalHeight,
                children: const <Widget>[
                  ColoredBox(
                    key: Key('short'),
                    color: Colors.red,
                    child: SizedBox(height: 40),
                  ),
                  ColoredBox(
                    key: Key('tall'),
                    color: Colors.blue,
                    child: SizedBox(height: 100),
                  ),
                  ColoredBox(
                    key: Key('alone'),
                    color: Colors.green,
                    child: SizedBox(height: 60),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  double height(WidgetTester tester, String key) =>
      tester.getSize(find.byKey(Key(key))).height;

  testWidgets('equalHeight matches the tallest card in the row', (
    WidgetTester tester,
  ) async {
    await pump(tester, equalHeight: true);

    expect(height(tester, 'short'), 100);
    expect(height(tester, 'tall'), 100);
    expect(height(tester, 'alone'), 60);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cards keep their own height by default', (
    WidgetTester tester,
  ) async {
    await pump(tester, equalHeight: false);

    expect(height(tester, 'short'), 40);
    expect(height(tester, 'tall'), 100);
  });
}
