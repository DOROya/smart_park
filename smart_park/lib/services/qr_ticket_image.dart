/// The driver's QR ticket as a phone-friendly image, to keep in the gallery
/// and show at the gate without opening the app.
///
/// Unlike the receipt, this carries the QR code, so it is only ever saved
/// to the driver's own gallery, never shared from the app.
library;

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'local_save.dart';
import 'parking_receipt.dart' show ParkingReceipt, parkingReceiptPng;
import 'sales_report.dart' show formatSalesPeso, kSalesMonthNames;
import 'sales_report_pdf.dart' show pdfSafeText;

const PdfColor _ink = PdfColor.fromInt(0xFF1F2128);
const PdfColor _text = PdfColor.fromInt(0xFF2B2F38);
const PdfColor _muted = PdfColor.fromInt(0xFF6B7080);
const PdfColor _rule = PdfColor.fromInt(0xFFDCDFE5);
const PdfColor _accent = PdfColor.fromInt(0xFFF2C335);
const PdfColor _accentSoft = PdfColor.fromInt(0xFFFFF4CF);
const PdfColor _onInkMuted = PdfColor.fromInt(0xFFB4B8C2);

/// Saves the ticket image to the gallery's SmartPark album.
Future<void> saveQrTicketToGallery(ParkingReceipt ticket, String qrData) async {
  await saveImageToGallery(await buildQrTicketPng(ticket, qrData));
}

/// The ticket as a PNG, about 1070 x 1610 px.
Future<Uint8List> buildQrTicketPng(ParkingReceipt ticket, String qrData) async {
  return parkingReceiptPng(await buildQrTicketPdf(ticket, qrData), dpi: 340);
}

/// One 80 x 120 mm page: header, QR, plate and package.
Future<Uint8List> buildQrTicketPdf(ParkingReceipt t, String qrData) async {
  final String facility = pdfSafeText(
    t.facilityName.isEmpty ? 'SmartPark facility' : t.facilityName,
  );
  final String plate = pdfSafeText(t.plate).toUpperCase();
  final bool hasId = t.transactionId.isNotEmpty;

  final pw.Document doc = pw.Document(
    title: 'SmartPark ticket${hasId ? ' ${t.number}' : ''}',
    author: 'SmartPark',
    creator: 'SmartPark',
  );

  pw.Widget small(String text, {PdfColor color = _muted}) => pw.Text(
    text,
    textAlign: pw.TextAlign.center,
    style: pw.TextStyle(fontSize: 7, color: color),
  );

  doc.addPage(
    pw.Page(
      pageFormat: const PdfPageFormat(
        80 * PdfPageFormat.mm,
        120 * PdfPageFormat.mm,
      ),
      margin: pw.EdgeInsets.zero,
      build: (pw.Context context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: <pw.Widget>[
          pw.Container(
            color: _ink,
            padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 11),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Row(
                  children: <pw.Widget>[
                    pw.Container(width: 3, height: 10, color: _accent),
                    pw.SizedBox(width: 5),
                    pw.Text(
                      'SmartPark',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.Spacer(),
                    pw.Text(
                      'PARKING TICKET',
                      style: pw.TextStyle(
                        fontSize: 6,
                        letterSpacing: 0.9,
                        fontWeight: pw.FontWeight.bold,
                        color: _accent,
                      ),
                    ),
                  ],
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  facility,
                  maxLines: 2,
                  style: pw.TextStyle(
                    fontSize: 11.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
                if (t.paidAt != null) ...<pw.Widget>[
                  pw.SizedBox(height: 2),
                  pw.Text(
                    'Paid ${_dateTime(t.paidAt!)}',
                    style: const pw.TextStyle(fontSize: 7, color: _onInkMuted),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Center(
            child: pw.Container(
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _rule, width: 0.8),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: qrData,
                width: 46 * PdfPageFormat.mm,
                height: 46 * PdfPageFormat.mm,
                color: _ink,
              ),
            ),
          ),
          pw.SizedBox(height: 10),
          if (plate.isNotEmpty)
            pw.Center(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: pw.BoxDecoration(
                  color: _accentSoft,
                  border: pw.Border.all(color: _accent, width: 0.8),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Text(
                  plate,
                  style: pw.TextStyle(
                    fontSize: 14,
                    letterSpacing: 1.2,
                    fontWeight: pw.FontWeight.bold,
                    color: _ink,
                  ),
                ),
              ),
            ),
          pw.SizedBox(height: 6),
          pw.Text(
            '${t.vehicleLabel} · ${t.packageLabel}',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: _text,
            ),
          ),
          if (t.amountCentavos > 0) ...<pw.Widget>[
            pw.SizedBox(height: 2),
            small('${formatSalesPeso(t.amountCentavos)} paid'),
          ],
          pw.Spacer(),
          pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 14),
            padding: const pw.EdgeInsets.only(top: 6, bottom: 10),
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: _rule, width: 0.6)),
            ),
            child: pw.Column(
              children: <pw.Widget>[
                small(
                  'Show this QR to the parking staff at the gate.',
                  color: _text,
                ),
                if (hasId) ...<pw.Widget>[
                  pw.SizedBox(height: 2),
                  small('Ticket ${t.number}'),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}

String _dateTime(DateTime d) {
  final int h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final String m = d.minute.toString().padLeft(2, '0');
  return '${kSalesMonthNames[d.month - 1].substring(0, 3)} ${d.day}, ${d.year}, '
      '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}
