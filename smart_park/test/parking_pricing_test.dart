import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/services/parking_pricing.dart';
import 'package:smart_park/services/platform_fees.dart';

void main() {
  group('parseAmount', () {
    test('reads numbers and the first number in text', () {
      expect(parseAmount(45), 45);
      expect(parseAmount('PHP 12.50/hr'), 12.5);
      expect(parseAmount('n/a'), 0);
      expect(parseAmount(null), 0);
      expect(parseAmount(<String, dynamic>{}), 0);
    });
  });

  group('VehicleRates', () {
    test('reads a rate map', () {
      final VehicleRates rates = VehicleRates.from(<String, dynamic>{
        'initial': '50',
        'succeedingHour': 20,
        'succeedingDaily': 'PHP 300',
      });
      expect(rates.initial, 50);
      expect(rates.succeedingHour, 20);
      expect(rates.succeedingDaily, 300);
      expect(rates.offersBase, isTrue);
      expect(rates.offersExtended, isTrue);
      expect(rates.offersDaily, isTrue);
    });

    test('a flat rate is the initial rate only', () {
      final VehicleRates rates = VehicleRates.from(30);
      expect(rates.initial, 30);
      expect(rates.offersExtended, isFalse);
      expect(rates.offersDaily, isFalse);
    });

    test('legacy keys are understood', () {
      final VehicleRates rates = VehicleRates.from(<String, dynamic>{
        'hourly': 40,
        'succeeding_hour': 15,
        'daily': 250,
      });
      expect(rates.initial, 40);
      expect(rates.succeedingHour, 15);
      expect(rates.succeedingDaily, 250);
    });
  });

  group('packageTotal (must match functions/src/pricing.js)', () {
    test('base charges the initial rate once', () {
      expect(packageTotal(plan: 'base', initialAmount: 50, duration: 9), 50);
    });

    test('extended adds succeeding hours', () {
      expect(
        packageTotal(
          plan: 'extended',
          initialAmount: 50,
          succeedingHourAmount: 20,
          duration: 3,
        ),
        110,
      );
    });

    test('daily multiplies the daily rate', () {
      expect(
        packageTotal(
          plan: 'daily',
          initialAmount: 0,
          dailyAmount: 300,
          duration: 2,
        ),
        600,
      );
    });
  });

  group('overtime', () {
    test('included time follows the plan', () {
      expect(includedStayHours(plan: 'base', duration: 5), 2);
      expect(includedStayHours(plan: 'extended', duration: 3), 5);
      expect(includedStayHours(plan: 'daily', duration: 2), 48);
      expect(includedStayHours(plan: 'daily', duration: 0), 24);
    });

    test('no overtime within included time plus grace', () {
      expect(overtimeHours(const Duration(hours: 2, minutes: 5), 2), 0);
      expect(overtimeHours(Duration.zero, 2), 0);
    });

    test('partial hours round up', () {
      expect(overtimeHours(const Duration(hours: 2, minutes: 6), 2), 1);
      expect(overtimeHours(const Duration(hours: 4, minutes: 5), 2), 2);
      expect(overtimeHours(const Duration(hours: 4, minutes: 6), 2), 3);
    });

    test('a daily ticket is not charged after two hours', () {
      final int included = includedStayHours(plan: 'daily', duration: 1);
      expect(overtimeHours(const Duration(hours: 10), included), 0);
      expect(overtimeHours(const Duration(hours: 25), included), 1);
    });

    test('ticket duration comes from the doc, else the QR payload', () {
      expect(ticketDuration(<String, dynamic>{'duration': 3}), 3);
      expect(
        ticketDuration(<String, dynamic>{
          'qrCode': jsonEncode(<String, dynamic>{'duration': 4}),
        }),
        4,
      );
      expect(ticketDuration(<String, dynamic>{'qrCode': 'not json'}), 1);
      expect(ticketDuration(<String, dynamic>{}), 1);
    });

    test('overtime rate prefers the succeeding-hour rate', () {
      expect(
        resolveOvertimeRate(<String, dynamic>{
          'car': <String, dynamic>{'initial': 50, 'succeedingHour': 20},
        }, 'car'),
        20,
      );
      expect(
        resolveOvertimeRate(<String, dynamic>{
          'car': <String, dynamic>{'initial': 'PHP 50'},
        }, 'car'),
        50,
      );
      expect(resolveOvertimeRate(<String, dynamic>{'car': 30}, 'car'), 30);
      expect(resolveOvertimeRate(<String, dynamic>{}, 'car'), isNull);
      expect(resolveOvertimeRate(null, 'car'), isNull);
    });
  });

  group('platform fees (must match functions/src/pricing.js)', () {
    test('commission is 5% rounded to the centavo', () {
      expect(platformFeeCentavosFor(5000), 250);
      expect(platformFeeCentavosFor(3333), 167);
    });

    test('processor fee estimate depends on the method', () {
      expect(
        estimateProcessorFeeCentavos(
          grossAmountCentavos: 10000,
          paymentMethodApiType: 'card',
        ),
        350,
      );
      expect(
        estimateProcessorFeeCentavos(
          grossAmountCentavos: 10000,
          paymentMethodApiType: 'qrph',
        ),
        134,
      );
    });
  });
}
