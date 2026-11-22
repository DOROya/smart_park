import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/screens/admin/admin_payment_health.dart';

Map<String, dynamic> reply({
  String status = 'ok',
  List<String> problems = const <String>[],
  int stuck = 0,
  int failedRefunds = 0,
}) => <String, dynamic>{
  'periodDays': 7,
  'status': status,
  'problems': problems,
  'paid': 40,
  'confirmedInApp': 37,
  'rescued': 3,
  'rescuedPercent': 7.5,
  'unfinished': <String, dynamic>{
    'gateTimedOut': 1,
    'gateCancelled': 2,
    'gateFailedToStart': 0,
    'checkoutsAbandoned': 1,
  },
  'inProgress': 2,
  'stuck': stuck,
  'refunds': <String, dynamic>{
    'inFlight': 1,
    'failed': failedRefunds,
    'slow': 0,
  },
  'reconcile': <String, dynamic>{'lastRunMinutesAgo': 6, 'overdue': false},
  'series': <Map<String, dynamic>>[
    <String, dynamic>{
      'date': '2026-11-21',
      'confirmedInApp': 18,
      'rescued': 2,
      'unfinished': 1,
    },
    <String, dynamic>{
      'date': '2026-11-22',
      'confirmedInApp': 19,
      'rescued': 1,
      'unfinished': 3,
    },
  ],
  'rescuedRecent': <Map<String, dynamic>>[
    <String, dynamic>{
      'establishmentName': 'Lot A',
      'amount': 60,
      'kind': 'gate',
      'paidAt': '2026-11-22T05:30:00.000Z',
    },
  ],
};

Widget host(Future<PaymentHealth> Function(int days) load) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(child: AdminPaymentHealthCard(load: load)),
  ),
);

void main() {
  test('reads the function reply', () {
    final PaymentHealth h = PaymentHealth.fromMap(reply());
    expect(h.ok, isTrue);
    expect(h.paid, 40);
    expect(h.rescued, 3);
    expect(h.unfinished, 4);
    expect(h.series.map((PaymentHealthDay d) => d.paid), <int>[20, 20]);
    expect(h.rescuedRecent.single.establishmentName, 'Lot A');
    expect(h.lastRunMinutesAgo, 6);
  });

  test('a reply missing parts still reads', () {
    final PaymentHealth h = PaymentHealth.fromMap(<String, dynamic>{});
    expect(h.ok, isFalse);
    expect(h.paid, 0);
    expect(h.series, isEmpty);
    expect(h.lastRunMinutesAgo, isNull);
  });

  test('run label', () {
    expect(paymentHealthRunLabel(null), 'never');
    expect(paymentHealthRunLabel(0), 'just now');
    expect(paymentHealthRunLabel(14), '14 min ago');
    expect(paymentHealthRunLabel(150), '2 h ago');
    expect(paymentHealthRunLabel(60 * 72), '3 days ago');
  });

  testWidgets('healthy: shows the figures and the rescued examples', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host((_) async => PaymentHealth.fromMap(reply())));
    await tester.pumpAndSettle();
    expect(find.text('All payments healthy'), findsOneWidget);
    expect(find.text('15-minute check last ran 6 min ago.'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
    expect(find.text('7.5% of paid'), findsOneWidget);
    expect(find.text('Ended without payment: 4'), findsOneWidget);
    expect(find.textContaining('Lot A'), findsOneWidget);
  });

  testWidgets('problems are listed', (WidgetTester tester) async {
    await tester.pumpWidget(
      host(
        (_) async => PaymentHealth.fromMap(
          reply(
            status: 'attention',
            problems: <String>['1 payment is stuck in progress.'],
            stuck: 1,
            failedRefunds: 2,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('• 1 payment is stuck in progress.'), findsOneWidget);
    expect(find.text('1 stuck'), findsOneWidget);
    expect(find.text('2 failed'), findsOneWidget);
  });

  testWidgets('switching the period asks again for that many days', (
    WidgetTester tester,
  ) async {
    final List<int> asked = <int>[];
    await tester.pumpWidget(
      host((int days) async {
        asked.add(days);
        return PaymentHealth.fromMap(reply());
      }),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last 30 days'));
    await tester.pumpAndSettle();
    expect(asked, <int>[7, 30]);
  });

  testWidgets('an error is shown instead of the figures', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host((_) => Future<PaymentHealth>.error(StateError('offline'))),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
  });

  testWidgets('fits a small phone', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host((_) async => PaymentHealth.fromMap(reply())));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
