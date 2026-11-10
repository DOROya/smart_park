import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/services/parking_receipt.dart';

final Map<String, dynamic> ticket = <String, dynamic>{
  'establishmentName': 'Juliville Parking – Main',
  'amount': 60,
  'createdAt': DateTime(2026, 11, 8, 15, 5),
  'paymentMethod': 'gcash',
  'paymongo': <String, dynamic>{'referenceNumber': 'ABC123XYZ'},
  'driverName': 'Isaiah Calamba',
  'vehicleType': 'car',
  'vehiclePlate': 'abc 1234',
  'plan': 'extended',
  'duration': 3,
  'entryAt': DateTime(2026, 11, 8, 15, 20),
  'exitAt': DateTime(2026, 11, 8, 21, 45),
  'staySeconds': 6 * 3600 + 25 * 60,
  'overtimeHours': 2,
  'overtimeAmount': 40,
  'overtimeStatus': 'collected',
  'overtimeCollectedAt': DateTime(2026, 11, 8, 21, 46),
};

void main() {
  test('reads a ticket into receipt fields', () {
    final ParkingReceipt r = ParkingReceipt.fromTicket(
      '7fq2k9x1abCDEFGH1234',
      ticket,
    );
    expect(r.number, 'SP-7FQ2K9X1AB');
    expect(r.fileName, 'SmartPark-Receipt-SP-7FQ2K9X1AB.pdf');
    expect(r.amountCentavos, 6000);
    expect(r.paymentMethodLabel, 'GCash');
    expect(r.reference, 'ABC123XYZ');
    expect(r.packageLabel, 'Extended (2 hrs + 3 hrs)');
    expect(r.coveredHours, 5);
    expect(r.hasOvertime, isTrue);
    expect(r.overtimeCollected, isTrue);
    expect(r.overtimeCentavos, 4000);
  });

  test('plain tickets read sensibly', () {
    final ParkingReceipt r = ParkingReceipt.fromTicket('x', <String, dynamic>{
      'amount': 30,
      'paymentMethod': 'paymaya',
    });
    expect(r.packageLabel, 'Base package (2 hrs)');
    expect(r.paymentMethodLabel, 'Maya');
    expect(r.vehicleLabel, 'Vehicle');
    expect(r.hasOvertime, isFalse);
  });

  test('builds a receipt PDF, with and without overtime', () async {
    for (final Map<String, dynamic> data in <Map<String, dynamic>>[
      ticket,
      <String, dynamic>{'amount': 30, 'establishmentName': 'Lot 🚗'},
    ]) {
      final Uint8List bytes = await buildParkingReceiptPdf(
        ParkingReceipt.fromTicket('7fq2k9x1abCDEFGH1234', data),
        generatedAt: DateTime(2026, 11, 10),
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      final String? out = Platform.environment['RECEIPT_OUT'];
      if (out != null && data == ticket) File(out).writeAsBytesSync(bytes);
    }
  });
}
