/// A driver's receipt for one paid parking ticket, as a shareable PDF.
///
/// The ticket's QR code is deliberately left off: anyone holding it could
/// use the ticket, and a receipt gets forwarded and printed.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Rect;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'gate_scan_service.dart'
    show kOvertimeCashDue, kOvertimeCollected, overtimeStatusOf;
import 'local_save.dart';
import 'parking_pricing.dart' show includedStayHours, kBaseStayHours;
import 'sales_report.dart' show formatSalesPeso, kSalesMonthNames;
import 'sales_report_pdf.dart' show pdfSafeText;

/// What a receipt shows, read from a `transactions` doc.
class ParkingReceipt {
  const ParkingReceipt({
    required this.transactionId,
    required this.facilityName,
    required this.amountCentavos,
    this.paidAt,
    this.paymentMethod = '',
    this.reference = '',
    this.driverName = '',
    this.vehicleType = '',
    this.plate = '',
    this.plan = '',
    this.duration = 0,
    this.entryAt,
    this.exitAt,
    this.staySeconds,
    this.overtimeHours = 0,
    this.overtimeCentavos = 0,
    this.overtimeStatus = '',
    this.overtimeCollectedAt,
  });

  factory ParkingReceipt.fromTicket(String id, Map<String, dynamic> data) {
    String text(String key) => ((data[key] as String?) ?? '').trim();
    final Object? paymongo = data['paymongo'];
    return ParkingReceipt(
      transactionId: id,
      facilityName: text('establishmentName'),
      amountCentavos: (((data['amount'] as num?) ?? 0) * 100).round(),
      paidAt: _date(data['createdAt']) ?? _date(data['createdAtClient']),
      paymentMethod: text('paymentMethod'),
      reference: paymongo is Map
          ? ((paymongo['referenceNumber'] as String?) ?? '').trim()
          : '',
      driverName: text('driverName'),
      vehicleType: text('vehicleType'),
      plate: text('vehiclePlate'),
      plan: text('plan').toLowerCase(),
      duration: ((data['duration'] as num?) ?? 0).toInt(),
      entryAt: _date(data['entryAt']),
      exitAt: _date(data['exitAt']),
      staySeconds: (data['staySeconds'] as num?)?.toInt(),
      overtimeHours: ((data['overtimeHours'] as num?) ?? 0).toInt(),
      overtimeCentavos: (((data['overtimeAmount'] as num?) ?? 0) * 100).round(),
      overtimeStatus: overtimeStatusOf(data),
      overtimeCollectedAt: _date(data['overtimeCollectedAt']),
    );
  }

  final String transactionId;
  final String facilityName;
  final int amountCentavos;
  final DateTime? paidAt;

  /// PayMongo's payment type, e.g. `gcash` or `card`.
  final String paymentMethod;

  /// PayMongo's reference number, when the checkout recorded one.
  final String reference;
  final String driverName;
  final String vehicleType;
  final String plate;
  final String plan;
  final int duration;
  final DateTime? entryAt;
  final DateTime? exitAt;
  final int? staySeconds;
  final int overtimeHours;
  final int overtimeCentavos;
  final String overtimeStatus;
  final DateTime? overtimeCollectedAt;

  bool get hasOvertime => overtimeHours > 0 && overtimeCentavos > 0;

  bool get overtimeCollected => overtimeStatus == kOvertimeCollected;

  /// e.g. "SP-7FQ2K9X1AB": short enough to read out, unique enough to find.
  String get number {
    final String id = transactionId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    return 'SP-${(id.length > 10 ? id.substring(0, 10) : id).toUpperCase()}';
  }

  /// e.g. "SmartPark-Receipt-SP-7FQ2K9X1AB.pdf".
  String get fileName => 'SmartPark-Receipt-$number.pdf';

  /// "GCash", "Card", "Maya"...
  String get paymentMethodLabel => switch (paymentMethod.toLowerCase()) {
    'card' => 'Card',
    'gcash' => 'GCash',
    'paymaya' || 'maya' => 'Maya',
    'shopeepay' => 'ShopeePay',
    'qrph' => 'QR Ph',
    'grab_pay' || 'grabpay' => 'GrabPay',
    '' => 'PayMongo',
    final String other => '${other[0].toUpperCase()}${other.substring(1)}',
  };

  String get vehicleLabel => switch (vehicleType.toLowerCase()) {
    '' => 'Vehicle',
    'car' => 'Car',
    'motorcycle' => 'Motorcycle',
    final String other => '${other[0].toUpperCase()}${other.substring(1)}',
  };

  /// e.g. "Base package (2 hrs)", "Extended (2 hrs + 3 hrs)", "2 days".
  String get packageLabel {
    final int n = duration < 1 ? 1 : duration;
    String plural(String unit) => '$n $unit${n == 1 ? '' : 's'}';
    return switch (plan) {
      'extended' => 'Extended ($kBaseStayHours hrs + ${plural('hr')})',
      'daily' => 'Daily (${plural('day')})',
      'weekly' => 'Weekly (${plural('week')})',
      'monthly' => 'Monthly (${plural('month')})',
      _ => 'Base package ($kBaseStayHours hrs)',
    };
  }

  /// Hours of parking the payment covers.
  int get coveredHours =>
      includedStayHours(plan: plan.isEmpty ? 'base' : plan, duration: duration);
}

DateTime? _date(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  if (value is num) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  return null;
}

/// How a receipt is saved or shared.
enum ReceiptFormat { pdf, png }

/// Loads the ticket, then saves or shares its receipt (see
/// [exportParkingReceiptAs]). Falls back to [fallback] (built from what the
/// app already knows) if the ticket can't be read in time, e.g. on a slow
/// network right after paying.
Future<bool> exportParkingReceipt({
  required String transactionId,
  ReceiptFormat format = ReceiptFormat.pdf,
  bool save = false,
  ParkingReceipt? fallback,
  Rect? origin,
}) async {
  ParkingReceipt? receipt;
  try {
    final DocumentSnapshot<Map<String, dynamic>> doc = await FirebaseFirestore
        .instance
        .collection('transactions')
        .doc(transactionId)
        .get()
        .timeout(const Duration(seconds: 10));
    final Map<String, dynamic>? data = doc.data();
    if (data != null) receipt = ParkingReceipt.fromTicket(doc.id, data);
  } on TimeoutException {
    if (fallback == null) rethrow;
  } on FirebaseException {
    if (fallback == null) rethrow;
  }
  receipt ??= fallback;
  if (receipt == null) {
    throw StateError('Ticket $transactionId not found.');
  }
  return exportParkingReceiptAs(receipt, format, save: save, origin: origin);
}

/// [receipt] as a PDF or a PNG image. With [save], the image goes to the
/// gallery and the PDF to Downloads (see [saveFileToDevice]); otherwise the
/// share sheet opens. Returns false if nothing was saved on the device.
Future<bool> exportParkingReceiptAs(
  ParkingReceipt receipt,
  ReceiptFormat format, {
  bool save = false,
  Rect? origin,
}) async {
  final Uint8List pdf = await buildParkingReceiptPdf(receipt);
  if (format == ReceiptFormat.pdf) {
    if (save) {
      return saveFileToDevice(
        bytes: pdf,
        fileName: receipt.fileName,
        mimeType: 'application/pdf',
      );
    }
    await Printing.sharePdf(
      bytes: pdf,
      filename: receipt.fileName,
      bounds: origin,
    );
    return true;
  }
  final Uint8List png = await parkingReceiptPng(pdf);
  if (save) {
    await saveImageToGallery(png);
    return true;
  }
  final String name = receipt.fileName.replaceFirst(RegExp(r'\.pdf$'), '.png');
  await SharePlus.instance.share(
    ShareParams(
      files: <XFile>[XFile.fromData(png, mimeType: 'image/png', name: name)],
      fileNameOverrides: <String>[name],
      subject: 'SmartPark receipt ${receipt.number}',
      sharePositionOrigin: origin,
    ),
  );
  return true;
}

/// The first page of [pdf] rendered as a PNG (the receipt at 220 dpi is
/// about 1280 x 1820 px, sharp enough to read when zoomed).
///
/// The raster is transparent wherever the page draws nothing, which a
/// dark-mode gallery shows as black, hiding dark text and the QR code. So
/// the page is flattened onto white: the image always looks like paper.
Future<Uint8List> parkingReceiptPng(Uint8List pdf, {double dpi = 220}) async {
  await for (final PdfRaster page in Printing.raster(
    pdf,
    pages: <int>[0],
    dpi: dpi,
  )) {
    final ui.Image raster = await page.toImage();
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, page.width.toDouble(), page.height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.drawImage(raster, ui.Offset.zero, ui.Paint());
    final ui.Image flat = await recorder.endRecording().toImage(
      page.width,
      page.height,
    );
    raster.dispose();
    try {
      final ByteData? png = await flat.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (png == null) throw StateError('Could not encode the receipt image.');
      return png.buffer.asUint8List();
    } finally {
      flat.dispose();
    }
  }
  throw StateError('The receipt has no page to render.');
}

// Same palette as the sales report.
const PdfColor _ink = PdfColor.fromInt(0xFF1F2128);
const PdfColor _text = PdfColor.fromInt(0xFF2B2F38);
const PdfColor _muted = PdfColor.fromInt(0xFF6B7080);
const PdfColor _rule = PdfColor.fromInt(0xFFDCDFE5);
const PdfColor _band = PdfColor.fromInt(0xFFF4F5F7);
const PdfColor _accent = PdfColor.fromInt(0xFFF2C335);
const PdfColor _accentSoft = PdfColor.fromInt(0xFFFFF4CF);
const PdfColor _paid = PdfColor.fromInt(0xFF1F7A4A);
const PdfColor _paidSoft = PdfColor.fromInt(0xFFE8F6EF);
const PdfColor _due = PdfColor.fromInt(0xFFB45309);
const PdfColor _onInk = PdfColor.fromInt(0xFFFFFFFF);
const PdfColor _onInkMuted = PdfColor.fromInt(0xFFB4B8C2);

/// Builds the receipt as an A5 PDF.
Future<Uint8List> buildParkingReceiptPdf(
  ParkingReceipt r, {
  DateTime? generatedAt,
}) async {
  final DateTime now = generatedAt ?? DateTime.now();
  final String facility = pdfSafeText(
    r.facilityName.isEmpty ? 'SmartPark facility' : r.facilityName,
  );
  final String driver = pdfSafeText(r.driverName);
  final String plate = pdfSafeText(r.plate).toUpperCase();

  final pw.Document doc = pw.Document(
    title: 'SmartPark receipt ${r.number}',
    author: 'SmartPark',
    creator: 'SmartPark',
    subject: facility,
  );

  pw.Widget label(String text) => pw.Text(
    text.toUpperCase(),
    style: pw.TextStyle(
      fontSize: 6.5,
      letterSpacing: 0.7,
      fontWeight: pw.FontWeight.bold,
      color: _muted,
    ),
  );

  pw.Widget section(String title) => pw.Container(
    margin: const pw.EdgeInsets.only(top: 14, bottom: 6),
    padding: const pw.EdgeInsets.only(bottom: 3),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _rule, width: 0.6)),
    ),
    child: pw.Row(
      children: <pw.Widget>[
        pw.Container(width: 2.5, height: 8, color: _accent),
        pw.SizedBox(width: 5),
        pw.Text(
          title.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 7.5,
            letterSpacing: 0.8,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
      ],
    ),
  );

  pw.Widget row(String key, String value, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2.2),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.SizedBox(
          width: 92,
          child: pw.Text(
            key,
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 8,
              color: _text,
              fontWeight: bold ? pw.FontWeight.bold : null,
            ),
          ),
        ),
      ],
    ),
  );

  pw.Widget charge(
    String what,
    String detail,
    int centavos, {
    PdfColor? tagColor,
    String? tag,
  }) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 6),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: _rule, width: 0.4)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Row(
                children: <pw.Widget>[
                  pw.Text(
                    what,
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      fontWeight: pw.FontWeight.bold,
                      color: _text,
                    ),
                  ),
                  if (tag != null) ...<pw.Widget>[
                    pw.SizedBox(width: 5),
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: tagColor!, width: 0.5),
                        borderRadius: pw.BorderRadius.circular(2),
                      ),
                      child: pw.Text(
                        tag.toUpperCase(),
                        style: pw.TextStyle(
                          fontSize: 5.5,
                          letterSpacing: 0.5,
                          fontWeight: pw.FontWeight.bold,
                          color: tagColor,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              pw.SizedBox(height: 1.5),
              pw.Text(
                detail,
                style: const pw.TextStyle(fontSize: 7, color: _muted),
              ),
            ],
          ),
        ),
        pw.Text(
          formatSalesPeso(centavos),
          style: const pw.TextStyle(fontSize: 8.5, color: _text),
        ),
      ],
    ),
  );

  pw.Widget total(String what, int centavos, {bool strong = false}) =>
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        color: strong ? _accentSoft : null,
        child: pw.Row(
          children: <pw.Widget>[
            pw.Expanded(
              child: pw.Text(
                what,
                style: pw.TextStyle(
                  fontSize: strong ? 9 : 8,
                  fontWeight: pw.FontWeight.bold,
                  color: strong ? _ink : _muted,
                ),
              ),
            ),
            pw.Text(
              formatSalesPeso(centavos),
              style: pw.TextStyle(
                fontSize: strong ? 10 : 8,
                fontWeight: pw.FontWeight.bold,
                color: strong ? _ink : _muted,
              ),
            ),
          ],
        ),
      );

  final String paidWhen = r.paidAt == null ? '-' : _stamp(r.paidAt!);
  final Duration? stay = r.staySeconds != null
      ? Duration(seconds: r.staySeconds!)
      : (r.entryAt != null && r.exitAt != null
            ? r.exitAt!.difference(r.entryAt!)
            : null);

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5.copyWith(
        marginLeft: 30,
        marginRight: 30,
        marginTop: 28,
        marginBottom: 24,
      ),
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      ),
      build: (pw.Context context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          // Header.
          pw.Container(
            padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: const pw.BoxDecoration(
              color: _ink,
              borderRadius: pw.BorderRadius.only(
                topLeft: pw.Radius.circular(4),
                topRight: pw.Radius.circular(4),
              ),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: <pw.Widget>[
                      pw.Row(
                        children: <pw.Widget>[
                          pw.Container(
                            width: 12,
                            height: 12,
                            alignment: pw.Alignment.center,
                            decoration: const pw.BoxDecoration(
                              color: _accent,
                              borderRadius: pw.BorderRadius.all(
                                pw.Radius.circular(2.5),
                              ),
                            ),
                            child: pw.Text(
                              'P',
                              style: pw.TextStyle(
                                fontSize: 8,
                                fontWeight: pw.FontWeight.bold,
                                color: _ink,
                              ),
                            ),
                          ),
                          pw.SizedBox(width: 5),
                          pw.Text(
                            'SMARTPARK',
                            style: pw.TextStyle(
                              fontSize: 8,
                              letterSpacing: 1.4,
                              fontWeight: pw.FontWeight.bold,
                              color: _accent,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'Parking Receipt',
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                          color: _onInk,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        facility,
                        style: const pw.TextStyle(
                          fontSize: 8.5,
                          color: _onInkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: <pw.Widget>[
                    pw.Text(
                      'RECEIPT NO.',
                      style: pw.TextStyle(
                        fontSize: 6,
                        letterSpacing: 0.6,
                        fontWeight: pw.FontWeight.bold,
                        color: _onInkMuted,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      r.number,
                      style: pw.TextStyle(
                        fontSize: 9,
                        fontWeight: pw.FontWeight.bold,
                        color: _onInk,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          pw.Container(height: 2.5, color: _accent),

          // Amount.
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: <pw.Widget>[
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: <pw.Widget>[
                    label('Amount paid'),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      formatSalesPeso(r.amountCentavos),
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: _ink,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      '$paidWhen  ·  ${r.paymentMethodLabel}',
                      style: const pw.TextStyle(fontSize: 8, color: _muted),
                    ),
                  ],
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: pw.BoxDecoration(
                  color: _paidSoft,
                  border: pw.Border.all(color: _paid, width: 0.6),
                  borderRadius: pw.BorderRadius.circular(3),
                ),
                child: pw.Text(
                  'PAID',
                  style: pw.TextStyle(
                    fontSize: 8,
                    letterSpacing: 1,
                    fontWeight: pw.FontWeight.bold,
                    color: _paid,
                  ),
                ),
              ),
            ],
          ),

          // Details.
          section('Details'),
          row('Facility', facility),
          if (driver.isNotEmpty) row('Driver', driver),
          row('Vehicle', r.vehicleLabel),
          if (plate.isNotEmpty) row('Plate number', plate, bold: true),
          row('Package', '${r.packageLabel}, covers ${r.coveredHours} hrs'),
          row('Payment method', '${r.paymentMethodLabel} via PayMongo'),
          if (r.reference.isNotEmpty)
            row('Payment reference', pdfSafeText(r.reference)),
          row('Ticket ID', r.transactionId),

          // Charges.
          section('Charges'),
          charge(
            'Parking fee',
            '${r.packageLabel} · paid in the app',
            r.amountCentavos,
          ),
          if (r.hasOvertime)
            charge(
              'Overtime',
              '${r.overtimeHours} hr${r.overtimeHours == 1 ? '' : 's'} past '
                  'the paid time · cash at the gate'
                  '${r.overtimeCollected && r.overtimeCollectedAt != null ? ', ${_stamp(r.overtimeCollectedAt!)}' : ''}',
              r.overtimeCentavos,
              tag: r.overtimeCollected
                  ? 'Paid'
                  : r.overtimeStatus == kOvertimeCashDue
                  ? 'Not yet paid'
                  : 'Pending',
              tagColor: r.overtimeCollected ? _paid : _due,
            ),
          pw.SizedBox(height: 4),
          if (r.hasOvertime) ...<pw.Widget>[
            total('Paid in the app', r.amountCentavos),
            total(
              'Total for this stay',
              r.amountCentavos + r.overtimeCentavos,
              strong: true,
            ),
          ] else
            total('Total paid', r.amountCentavos, strong: true),

          // Stay.
          if (r.entryAt != null) ...<pw.Widget>[
            section('Latest stay'),
            row('Entered', _stamp(r.entryAt!)),
            if (r.exitAt != null) row('Exited', _stamp(r.exitAt!)),
            if (stay != null && r.exitAt != null)
              row('Time parked', _duration(stay)),
          ],

          pw.Spacer(),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            color: _band,
            child: pw.Text(
              'Acknowledgment receipt issued by SmartPark for a payment '
              'processed by PayMongo. This is not an official receipt (BIR); '
              'ask the facility if you need one. The ticket QR code is not '
              'shown here, so this receipt cannot be used to enter. '
              'Generated ${_stamp(now)}.',
              style: const pw.TextStyle(fontSize: 6.5, color: _muted),
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

String _stamp(DateTime t) {
  final int hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final String minute = t.minute.toString().padLeft(2, '0');
  return '${kSalesMonthNames[t.month - 1].substring(0, 3)} ${t.day}, ${t.year}, '
      '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// e.g. "2 hr 15 min", "45 min".
String _duration(Duration d) {
  final int h = d.inHours;
  final int m = d.inMinutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h hr' : '$h hr $m min';
}
