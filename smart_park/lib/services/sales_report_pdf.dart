import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'sales_report.dart';

/// Who the report is for, which decides its columns.
enum SalesReportAudience {
  /// A parking owner: their facility's gross, fees, payout and cash.
  owner,

  /// The admin: SmartPark's commission across all facilities. Gross sales
  /// are the owners' business, so the admin's report leaves them out.
  platform,
}

/// e.g. "Monthly Sales Report" or "Quarterly Commission Report".
String salesReportTitle(SalesReport report, SalesReportAudience audience) =>
    '${report.range.adjective} '
    '${audience == SalesReportAudience.owner ? 'Sales' : 'Commission'} Report';

/// e.g. "November 2026", or "Q4 2026 (Oct - Dec)" for a quarter.
String salesReportPeriod(SalesReport report) => report.range.months.isEmpty
    ? report.range.label
    : '${report.range.label} (${report.range.months})';

/// e.g. "SmartPark-Sales-2026-11.pdf".
String salesReportFileName(SalesReport report, SalesReportAudience audience) =>
    'SmartPark-'
    '${audience == SalesReportAudience.owner ? 'Sales' : 'Commission'}-'
    '${report.range.slug}.pdf';

/// Builds the printable sales report as PDF bytes.
///
/// [scopeLabel] names what the figures cover (the facility, or "All
/// facilities"); [preparedBy] is the signed-in account.
Future<Uint8List> buildSalesReportPdf({
  required SalesReport report,
  required SalesReportAudience audience,
  required String scopeLabel,
  required String preparedBy,
  PdfPageFormat format = PdfPageFormat.a4,
  DateTime? generatedAt,
}) async {
  final DateTime now = generatedAt ?? DateTime.now();
  scopeLabel = pdfSafeText(scopeLabel);
  preparedBy = pdfSafeText(preparedBy);
  final bool owner = audience == SalesReportAudience.owner;
  final bool daily = report.breakdown == SalesBreakdown.daily;
  final String title = salesReportTitle(report, audience);
  final String period = salesReportPeriod(report);

  final List<String> headers = <String>[
    daily ? 'Date' : 'Month',
    'Txns',
    if (owner) 'Gross sales',
    'Commission',
    if (owner) ...<String>[
      'Processing (est.)',
      'Payout (est.)',
      'Overtime cash',
    ],
  ];

  List<String> cells(String label, SalesRow r) => <String>[
    label,
    '${r.count}',
    if (owner) formatSalesPeso(r.grossCentavos),
    formatSalesPeso(r.commissionCentavos),
    if (owner) ...<String>[
      formatSalesPeso(r.processingCentavos),
      formatSalesPeso(r.payoutCentavos),
      formatSalesPeso(r.cashCentavos),
    ],
  ];

  final List<List<String>> data = <List<String>>[
    for (final SalesRow row in report.rows)
      cells(
        daily
            ? '${report.rowLabel(row)} (${salesWeekday(row.start)})'
            : report.rowLabel(row),
        row,
      ),
  ];

  const PdfColor ink = PdfColor.fromInt(0xFF1F2937);
  const PdfColor muted = PdfColor.fromInt(0xFF6B7280);
  const PdfColor rule = PdfColor.fromInt(0xFFD1D5DB);
  const PdfColor band = PdfColor.fromInt(0xFFF3F4F6);

  final pw.TextStyle small = const pw.TextStyle(fontSize: 8, color: muted);
  // Owners rank by sales, the admin by commission.
  int headline(SalesRow r) => owner ? r.grossCentavos : r.commissionCentavos;
  final SalesRow? best = report.bestBy(headline);

  pw.Widget summaryBox(String label, String value) => pw.Expanded(
    child: pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: rule, width: 0.6),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text(label, style: small),
          pw.SizedBox(height: 2),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: ink,
            ),
          ),
        ],
      ),
    ),
  );

  final pw.Document doc = pw.Document(
    title: '$title - $period',
    author: 'SmartPark',
    creator: 'SmartPark',
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: format.copyWith(
        marginLeft: 36,
        marginRight: 36,
        marginTop: 36,
        marginBottom: 36,
      ),
      header: (pw.Context context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text('$title - $period - $scopeLabel', style: small),
            ),
      footer: (pw.Context context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: rule, width: 0.6)),
        ),
        child: pw.Row(
          children: <pw.Widget>[
            pw.Expanded(
              child: pw.Text(
                'For internal record-keeping only. Not an official receipt '
                'or BIR-registered sales book.',
                style: small,
              ),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: small,
            ),
          ],
        ),
      ),
      build: (pw.Context context) => <pw.Widget>[
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: <pw.Widget>[
                  pw.Text(
                    'SmartPark',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: muted,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: ink,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    '$scopeLabel  |  $period',
                    style: const pw.TextStyle(fontSize: 11, color: ink),
                  ),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: <pw.Widget>[
                pw.Text('Generated ${_stamp(now)}', style: small),
                if (preparedBy.isNotEmpty)
                  pw.Text('Prepared by $preparedBy', style: small),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Row(
          children: <pw.Widget>[
            owner
                ? summaryBox(
                    'Gross sales',
                    formatSalesPeso(report.totals.grossCentavos),
                  )
                : summaryBox(
                    'SmartPark commission',
                    formatSalesPeso(report.totals.commissionCentavos),
                  ),
            pw.SizedBox(width: 8),
            summaryBox('Transactions', '${report.totals.count}'),
            pw.SizedBox(width: 8),
            owner
                ? summaryBox(
                    'Payout (estimate)',
                    formatSalesPeso(report.totals.payoutCentavos),
                  )
                : summaryBox(
                    'Per transaction',
                    report.totals.count == 0
                        ? '-'
                        : formatSalesPeso(
                            (report.totals.commissionCentavos /
                                    report.totals.count)
                                .round(),
                          ),
                  ),
            pw.SizedBox(width: 8),
            summaryBox(
              '${daily ? 'Best day' : 'Best month'}'
              '${best == null ? '' : ': ${report.rowLabel(best)}'}',
              best == null ? '-' : formatSalesPeso(headline(best)),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          headers: headers,
          data: <List<String>>[...data, cells('TOTAL', report.totals)],
          border: pw.TableBorder(
            horizontalInside: const pw.BorderSide(color: rule, width: 0.4),
            bottom: const pw.BorderSide(color: rule, width: 0.6),
            top: const pw.BorderSide(color: rule, width: 0.6),
          ),
          headerStyle: pw.TextStyle(
            fontSize: 8.5,
            fontWeight: pw.FontWeight.bold,
            color: ink,
          ),
          headerDecoration: const pw.BoxDecoration(color: band),
          cellStyle: const pw.TextStyle(fontSize: 8.5, color: ink),
          cellPadding: const pw.EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 3.5,
          ),
          cellAlignment: pw.Alignment.centerRight,
          cellAlignments: <int, pw.Alignment>{0: pw.Alignment.centerLeft},
          headerAlignments: <int, pw.Alignment>{0: pw.Alignment.centerLeft},
          headerAlignment: pw.Alignment.centerRight,
          // Bold, shaded totals row (row 0 is the header).
          cellDecoration: (int index, dynamic value, int rowNum) =>
              rowNum == data.length + 1
              ? const pw.BoxDecoration(color: band)
              : const pw.BoxDecoration(),
          textStyleBuilder: (int index, dynamic value, int rowNum) =>
              rowNum == data.length + 1
              ? pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: ink,
                )
              : null,
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          owner
              ? 'Gross sales are in-app payments for paid tickets. Commission '
                    'is SmartPark\'s fee; processing is an estimate of '
                    'PayMongo\'s fee, so the payout is an estimate too; '
                    'PayMongo\'s settlement report has the exact amounts. Overtime cash is '
                    'collected at the gate and counted on the day it was '
                    'collected.'
              : 'Commission is SmartPark\'s platform fee on in-app parking '
                    'payments, across all facilities.',
          style: small,
        ),
        pw.SizedBox(height: 36),
        pw.Row(
          children: <pw.Widget>[
            _signatureLine('Prepared by', small, rule),
            pw.SizedBox(width: 48),
            _signatureLine('Checked by', small, rule),
          ],
        ),
      ],
    ),
  );

  return doc.save();
}

/// Opens the system print dialog (which also offers Save as PDF).
Future<void> printSalesReport({
  required SalesReport report,
  required SalesReportAudience audience,
  required String scopeLabel,
  required String preparedBy,
}) {
  return Printing.layoutPdf(
    name: salesReportFileName(report, audience),
    onLayout: (PdfPageFormat format) => buildSalesReportPdf(
      report: report,
      audience: audience,
      scopeLabel: scopeLabel,
      preparedBy: preparedBy,
      format: format,
    ),
  );
}

/// Opens the share sheet with the report as a PDF file.
Future<void> shareSalesReport({
  required SalesReport report,
  required SalesReportAudience audience,
  required String scopeLabel,
  required String preparedBy,
}) async {
  final Uint8List bytes = await buildSalesReportPdf(
    report: report,
    audience: audience,
    scopeLabel: scopeLabel,
    preparedBy: preparedBy,
  );
  await Printing.sharePdf(
    bytes: bytes,
    filename: salesReportFileName(report, audience),
  );
}

pw.Widget _signatureLine(String label, pw.TextStyle style, PdfColor rule) =>
    pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Container(
            height: 0.6,
            color: rule,
            margin: const pw.EdgeInsets.only(bottom: 3),
          ),
          pw.Text(label, style: style),
        ],
      ),
    );

String _stamp(DateTime t) {
  final int hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final String minute = t.minute.toString().padLeft(2, '0');
  return '${kSalesMonthNames[t.month - 1].substring(0, 3)} ${t.day}, ${t.year} '
      '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
}

/// The built-in PDF font only covers Latin-1, so typed names lose anything
/// beyond it: smart quotes and dashes become plain ones, the rest is dropped
/// (e.g. emoji).
String pdfSafeText(String text) {
  const Map<int, String> plain = <int, String>{
    0x2018: "'",
    0x2019: "'",
    0x201C: '"',
    0x201D: '"',
    0x2013: '-',
    0x2014: '-',
    0x2026: '...',
    0x20B1: 'PHP ',
  };
  final StringBuffer out = StringBuffer();
  for (final int rune in text.runes) {
    if (rune <= 0xFF) {
      out.writeCharCode(rune);
    } else if (plain[rune] case final String replacement) {
      out.write(replacement);
    }
  }
  return out.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}
