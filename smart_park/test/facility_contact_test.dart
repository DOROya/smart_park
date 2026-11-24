import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/services/facility_contact.dart';
import 'package:smart_park/widgets/sp_facility_contact.dart';

void main() {
  test('mobiles are stored as +63, landlines as typed', () {
    expect(normalizeFacilityContact('0917 123 4567'), '+639171234567');
    expect(normalizeFacilityContact('+63 917-123-4567'), '+639171234567');
    expect(normalizeFacilityContact('8123-4567'), '8123-4567');
    expect(normalizeFacilityContact('02 8123 4567'), '02 8123 4567');
    // As the form's hint writes it.
    expect(normalizeFacilityContact('(02) 8123 4567'), '(02) 8123 4567');
    expect(normalizeFacilityContact(''), '');
    // Neither a mobile nor a landline.
    expect(normalizeFacilityContact('call me'), isNull);
    expect(normalizeFacilityContact('123'), isNull);
    expect(normalizeFacilityContact('1234 5678 9012 3456 7890 12'), isNull);
  });

  test('a stored mobile is shown the local way and dialed in full', () {
    expect(displayFacilityContact('+639171234567'), '0917 123 4567');
    expect(displayFacilityContact('8123-4567'), '8123-4567');
    expect(dialableFacilityContact('02 8123-4567'), '0281234567');
  });

  testWidgets('the row shows the number and Call only when there is one', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SpFacilityContactRow(stored: '+639171234567')),
      ),
    );
    expect(find.text('0917 123 4567'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SpFacilityContactRow(stored: '')),
      ),
    );
    expect(find.text('Call'), findsNothing);
  });
}
