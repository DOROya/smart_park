import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/services/driver_transactions.dart';
import 'package:smart_park/services/parking_refunds.dart';

void main() {
  Timestamp at(int day) => Timestamp.fromDate(DateTime(2026, 11, day, 9));

  test('payments and refunds are listed newest first, by kind', () {
    final List<DriverTransaction> list = driverTransactions(
      tickets: <String, Map<String, dynamic>>{
        't1': <String, dynamic>{
          'status': 'paid',
          'amount': 100,
          'paymentMethod': 'gcash',
          'plan': 'daily',
          'vehiclePlate': 'abc 123',
          'establishmentName': 'Lot A',
          'createdAt': at(1),
          'overtimeStatus': 'collected',
          'overtimeAmount': 40,
          'overtimeHours': 2,
          'overtimeCollectedAt': at(3),
        },
        // Never paid: no line.
        't2': <String, dynamic>{'status': 'failed', 'amount': 50},
      },
      payments: <Map<String, dynamic>>[
        <String, dynamic>{
          'kind': 'extra_hours',
          'status': 'paid',
          'ticketId': 't1',
          'hours': 3,
          'amount': 60,
          'paymentMethod': 'card',
          'createdAt': at(2),
        },
        // The ticket's own payment is already listed from the ticket.
        <String, dynamic>{'status': 'paid', 'amount': 100, 'createdAt': at(1)},
      ],
      refunds: <ParkingRefund>[
        ParkingRefund.fromMap('t1', <String, dynamic>{
          'status': 'refunded',
          'amountCentavos': 2500,
          'refundedAt': at(4),
        }),
        ParkingRefund.fromMap('t2', <String, dynamic>{
          'status': 'requested',
          'amountCentavos': 900,
        }),
      ],
    );

    expect(list.map((DriverTransaction t) => t.kind), <DriverTransactionKind>[
      DriverTransactionKind.refund,
      DriverTransactionKind.overtime,
      DriverTransactionKind.extraHours,
      DriverTransactionKind.ticket,
    ]);
    expect(
      list.every((DriverTransaction t) => t.facilityName == 'Lot A'),
      isTrue,
    );
    expect(list[0].amountCentavos, 2500);
    expect(list[0].isRefund, isTrue);
    expect(list[1].method, 'Cash');
    expect(list[2].method, 'Card');
    expect(list[2].detail, '3 hours added to the ticket');
    expect(list[3].amountCentavos, 10000);
    expect(list[3].detail, 'Daily · ABC 123');
  });
}
