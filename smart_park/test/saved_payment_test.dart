import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/screens/driver/driver_checkout_payment_page.dart';
import 'package:smart_park/screens/driver/driver_parking_pass_page.dart';
import 'package:smart_park/screens/driver/driver_payment_page.dart';
import 'package:smart_park/screens/driver/widgets/driver_active_pass_bar.dart';
import 'package:smart_park/services/saved_payment.dart';

void main() {
  group('mobile numbers', () {
    test('are normalized like the server does', () {
      for (final String raw in <String>[
        '09171234567',
        '0917 123 4567',
        '9171234567',
        '+63 917-123-4567',
        '639171234567',
      ]) {
        expect(normalizePhMobile(raw), '+639171234567', reason: raw);
      }
      for (final String raw in <String>['', '0817 123 4567', '0917123456']) {
        expect(normalizePhMobile(raw), isNull, reason: raw);
      }
    });
  });

  test('a saved number is shown the local way', () {
    expect(localPhMobile('+639171234567'), '0917 123 4567');
    expect(localPhMobile(''), '');
  });

  test('the Home shortcut lists usable QRs, the one being paid first', () {
    final DateTime now = DateTime(2026, 11, 20, 12);
    Timestamp at(int hour) => Timestamp.fromDate(DateTime(2026, 11, 20, hour));
    final List<ActivePass> passes = usablePasses(<ActivePass>[
      (
        id: 'old',
        data: <String, dynamic>{
          'status': 'awaiting_gate',
          'createdAt': at(8),
          'expiresAt': at(23),
        },
      ),
      (
        id: 'new',
        data: <String, dynamic>{
          'status': 'awaiting_gate',
          'createdAt': at(10),
          'expiresAt': at(23),
        },
      ),
      (
        id: 'paying',
        data: <String, dynamic>{'status': 'pending', 'createdAt': at(7)},
      ),
      (
        id: 'expired',
        data: <String, dynamic>{
          'status': 'awaiting_gate',
          'createdAt': at(11),
          'expiresAt': at(11),
        },
      ),
      (id: 'paid', data: <String, dynamic>{'status': 'paid'}),
    ], now);
    expect(passes.map((ActivePass p) => p.id), <String>[
      'paying',
      'new',
      'old',
    ]);
  });

  group('cards', () {
    test('numbers pass the Luhn check', () {
      expect(isValidCardNumber('4343 4343 4343 4345'), isTrue);
      expect(isValidCardNumber('4242424242424242'), isTrue);
      expect(isValidCardNumber('4242424242424241'), isFalse);
      expect(isValidCardNumber('1234'), isFalse);
    });

    test('expiry is MM/YY or MM/YYYY and not past', () {
      final DateTime now = DateTime(2026, 11, 20);
      expect(parseCardExpiry('12/30', now: now), (month: 12, year: 2030));
      expect(parseCardExpiry('1/2027', now: now), (month: 1, year: 2027));
      expect(parseCardExpiry('11/26', now: now), (month: 11, year: 2026));
      expect(parseCardExpiry('10/26', now: now), isNull);
      expect(parseCardExpiry('13/30', now: now), isNull);
      expect(parseCardExpiry('1230', now: now), isNull);
    });

    test('CVC is 3 or 4 digits', () {
      expect(isValidCvc('123'), isTrue);
      expect(isValidCvc('1234'), isTrue);
      expect(isValidCvc('12'), isFalse);
      expect(isValidCvc('12a'), isFalse);
    });

    test('are not saved without the PayMongo public key', () async {
      expect(canSaveCards, isFalse);
      await expectLater(
        savePayMongoCard(
          number: '4343434343434345',
          expMonth: 12,
          expYear: 2030,
          cvc: '123',
          name: 'Juan',
        ),
        throwsA(isA<CardSaveException>()),
      );
    });
  });

  test('the QR shows the saved details masked', () {
    expect(
      savedPaymentLabel('GCash', <String, dynamic>{'phone': '+639171234567'}),
      'GCash 0917 ••• 4567',
    );
    expect(
      savedPaymentLabel('Card', <String, dynamic>{
        'cardPaymentMethodId': 'pm_1',
        'cardLast4': '4345',
      }),
      'Card •••• 4345',
    );
    expect(savedPaymentLabel('GCash', null), '');
  });

  group('payment step', () {
    Future<List<(DriverPaymentMethod, SavedPaymentDetails)>> pumpPage(
      WidgetTester tester, {
      String initialMethod = '',
      String initialPhone = '',
    }) async {
      tester.view.physicalSize = const Size(1080, 2600);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      final List<(DriverPaymentMethod, SavedPaymentDetails)> calls =
          <(DriverPaymentMethod, SavedPaymentDetails)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: DriverCheckoutPaymentPage(
            establishmentName: 'Lot 1',
            vehicleLabel: 'Car',
            plan: 'Base',
            duration: 1,
            amount: 50,
            isPayMongoConfigured: true,
            initialMethodApiType: initialMethod,
            initialPhone: initialPhone,
            onProcessPayment:
                (DriverPaymentMethod method, SavedPaymentDetails saved) async {
                  calls.add((method, saved));
                  return false;
                },
          ),
        ),
      );
      return calls;
    }

    testWidgets('a GCash number is entered with the QR', (
      WidgetTester tester,
    ) async {
      final List<(DriverPaymentMethod, SavedPaymentDetails)> calls =
          await pumpPage(tester);
      await tester.tap(find.text('GCash'));
      await tester.pump();
      expect(find.text('GCash mobile number'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '12345');
      await tester.tap(find.text('Get Temporary QR'));
      await tester.pump();
      expect(find.textContaining('Enter your GCash number'), findsOneWidget);
      expect(calls, isEmpty);

      await tester.enterText(find.byType(TextField), '0917 123 4567');
      await tester.tap(find.text('Get Temporary QR'));
      await tester.pump();
      expect(calls, hasLength(1));
      expect(calls.single.$1, DriverPaymentMethod.gcash);
      expect(calls.single.$2.phone, '+639171234567');
    });

    testWidgets("last time's GCash number is filled in", (
      WidgetTester tester,
    ) async {
      final List<(DriverPaymentMethod, SavedPaymentDetails)> calls =
          await pumpPage(
            tester,
            initialMethod: 'gcash',
            initialPhone: '+639171234567',
          );
      // (The field's hint is the same example number, so read its value.)
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '0917 123 4567',
      );
      await tester.tap(find.text('Get Temporary QR'));
      await tester.pump();
      expect(calls.single.$1, DriverPaymentMethod.gcash);
      expect(calls.single.$2.phone, '+639171234567');
    });

    testWidgets('without the public key a card is entered at the gate', (
      WidgetTester tester,
    ) async {
      final List<(DriverPaymentMethod, SavedPaymentDetails)> calls =
          await pumpPage(tester);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('payment page at the gate'), findsOneWidget);
      await tester.tap(find.text('Get Temporary QR'));
      await tester.pump();
      expect(calls.single.$1, DriverPaymentMethod.card);
      expect(calls.single.$2.cardPaymentMethodId, isEmpty);
    });
  });
}
