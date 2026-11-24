import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/widgets/sp_read_plate.dart';

void main() {
  Future<void> pumpButton(
    WidgetTester tester, {
    required List<String>? lines,
    required List<String> events,
    required ValueChanged<String> onPlate,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SpReadPlateButton(
          onPlate: onPlate,
          reader: () async => lines,
          knownPlates: () async => <String>['XYZ 9876'],
          pauseScanner: () async => events.add('stop'),
          resumeScanner: () async => events.add('start'),
        ),
      ),
    ),
  );

  testWidgets('the scanner stops for the photo and restarts after', (
    WidgetTester tester,
  ) async {
    final List<String> events = <String>[];
    String? filled;
    await pumpButton(
      tester,
      lines: <String>['PILIPINAS', 'XYZ 9876', 'ABC 1234'],
      events: events,
      onPlate: (String p) => filled = p,
    );
    await tester.tap(find.byIcon(Icons.photo_camera_outlined));
    await tester.pumpAndSettle();
    expect(events, <String>['stop']);
    // The known plate is the best guess; nothing is filled yet.
    expect(find.text('XYZ 9876'), findsWidgets);
    expect(filled, isNull);
    await tester.tap(find.text('Use this plate'));
    await tester.pumpAndSettle();
    expect(filled, 'XYZ 9876');
    expect(events, <String>['stop', 'start']);
  });

  testWidgets('nothing plate-like: a message, and nothing is filled', (
    WidgetTester tester,
  ) async {
    final List<String> events = <String>[];
    String? filled;
    await pumpButton(
      tester,
      lines: <String>['WELCOME'],
      events: events,
      onPlate: (String p) => filled = p,
    );
    await tester.tap(find.byIcon(Icons.photo_camera_outlined));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't read a plate"), findsOneWidget);
    // Closing the sheet fills nothing and restarts the scanner.
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(filled, isNull);
    expect(events, <String>['stop', 'start']);
  });
}
