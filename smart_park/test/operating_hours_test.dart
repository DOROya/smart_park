import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/services/operating_hours.dart';

void main() {
  test('structured fields win over the text', () {
    final OperatingHours hours = OperatingHours.parse(<String, dynamic>{
      'openTime': '06:30',
      'closeTime': '22:00',
      'operatingHours': 'garbage',
    });
    expect(hours.openMinutes, 390);
    expect(hours.closeMinutes, 1320);
    expect(hours.label, '6:30 AM - 10:00 PM');
  });

  test('legacy text is parsed', () {
    final OperatingHours hours = OperatingHours.parseText('6:00 AM - 10:00 PM');
    expect(hours.openMinutes, 360);
    expect(hours.closeMinutes, 1320);
    expect(OperatingHours.parseText('7am – 9pm').label, '7:00 AM - 9:00 PM');
    expect(OperatingHours.parseText('whenever').isSet, isFalse);
  });

  test('24-hour text and flag', () {
    expect(OperatingHours.parseText('Open 24 hours').allDay, isTrue);
    expect(OperatingHours.parseText('24/7').allDay, isTrue);
    expect(
      OperatingHours.parse(<String, dynamic>{'open24Hours': true}).label,
      'Open 24 hours',
    );
    // A time with :24 in it is not "24 hours".
    expect(OperatingHours.parseText('12:24 AM - 8:00 PM').allDay, isFalse);
  });

  test('open-now handles day and overnight hours', () {
    const OperatingHours day = OperatingHours(
      openMinutes: 6 * 60,
      closeMinutes: 22 * 60,
    );
    expect(day.isOpenAt(DateTime(2026, 1, 1, 12)), isTrue);
    expect(day.isOpenAt(DateTime(2026, 1, 1, 22)), isFalse);
    expect(day.isOpenAt(DateTime(2026, 1, 1, 5, 59)), isFalse);

    const OperatingHours night = OperatingHours(
      openMinutes: 18 * 60,
      closeMinutes: 2 * 60,
    );
    expect(night.overnight, isTrue);
    expect(night.isOpenAt(DateTime(2026, 1, 1, 23)), isTrue);
    expect(night.isOpenAt(DateTime(2026, 1, 1, 1)), isTrue);
    expect(night.isOpenAt(DateTime(2026, 1, 1, 12)), isFalse);
  });

  test('saved fields round-trip', () {
    const OperatingHours hours = OperatingHours(
      openMinutes: 8 * 60,
      closeMinutes: 17 * 60 + 30,
    );
    final Map<String, dynamic> saved = hours.toFirestore();
    expect(saved['openTime'], '08:00');
    expect(saved['closeTime'], '17:30');
    expect(saved['operatingHours'], '8:00 AM - 5:30 PM');
    expect(OperatingHours.parse(saved).label, hours.label);
  });
}
