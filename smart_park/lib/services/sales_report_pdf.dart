import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'sales_report.dart';
import 'sales_report_summary.dart';

export 'sales_report_summary.dart';

// Brand: SmartPark yellow on near-black ink.
const PdfColor _ink = PdfColor.fromInt(0xFF1F2128);
const PdfColor _text = PdfColor.fromInt(0xFF2B2F38);
const PdfColor _muted = PdfColor.fromInt(0xFF6B7080);
const PdfColor _rule = PdfColor.fromInt(0xFFDCDFE5);
const PdfColor _band = PdfColor.fromInt(0xFFF4F5F7);
const PdfColor _accent = PdfColor.fromInt(0xFFF2C335);
const PdfColor _accentSoft = PdfColor.fromInt(0xFFFFF4CF);
const PdfColor _previous = PdfColor.fromInt(0xFFC9CCD4);
const PdfColor _up = PdfColor.fromInt(0xFF1F7A4A);
const PdfColor _down = PdfColor.fromInt(0xFFB3261E);
const PdfColor _onInk = PdfColor.fromInt(0xFFFFFFFF);
const PdfColor _onInkMuted = PdfColor.fromInt(0xFFB4B8C2);

/// Builds the printable sales report as PDF bytes.
///
/// [scopeLabel] names what the figures cover (the facility, or "All
/// facilities"); [preparedBy] is the signed-in account. With [previous]
/// (see [SalesReport.prior]) the report compares the two periods.
Future<Uint8List> buildSalesReportPdf({
  required SalesReport report,
  required SalesReportAudience audience,
  required String scopeLabel,
  required String preparedBy,
  SalesReport? previous,
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
  final List<SalesMetric> metrics = salesMetrics(report, previous, audience);

  final pw.Document doc = pw.Document(
    title: '$title - $period',
    author: 'SmartPark',
    creator: 'SmartPark',
    subject: scopeLabel,
  );

  // Headline cards: the headline, transactions, the average sale, and the
  // owner's take-home (or, for the admin, days with sales).
  final List<(String, SalesMetric)> cards = <(String, SalesMetric)>[
    (metrics[0].label, metrics[0]),
    ('Transactions', metrics[1]),
    ('Avg. per transaction', metrics[2]),
    owner ? ('Take-home (est.)', metrics[7]) : (metrics[3].label, metrics[3]),
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: format.copyWith(
        marginLeft: 36,
        marginRight: 36,
        marginTop: 32,
        marginBottom: 28,
      ),
      theme: pw.ThemeData.withFont(
        base: pw.Font.helvetica(),
        bold: pw.Font.helveticaBold(),
      ),
      header: (pw.Context context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Container(
              margin: const pw.EdgeInsets.only(bottom: 12),
              padding: const pw.EdgeInsets.only(bottom: 6),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: _accent, width: 1.5),
                ),
              ),
              child: pw.Row(
                children: <pw.Widget>[
                  pw.Text(
                    'SMARTPARK',
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.2,
                      color: _ink,
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Text(
                      '$title  ·  $period  ·  $scopeLabel',
                      style: const pw.TextStyle(fontSize: 8, color: _muted),
                    ),
                  ),
                ],
              ),
            ),
      footer: (pw.Context context) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 10),
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _rule, width: 0.6)),
        ),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            pw.Expanded(
              child: pw.Text(
                'Confidential. For internal record-keeping only; not an '
                'official receipt or BIR-registered sales book.',
                style: const pw.TextStyle(fontSize: 7, color: _muted),
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(
                fontSize: 7,
                color: _muted,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      build: (pw.Context context) => <pw.Widget>[
        _titleBlock(
          title: title,
          scopeLabel: scopeLabel,
          report: report,
          previous: previous,
          preparedBy: preparedBy,
          generated: _stamp(now),
        ),
        pw.SizedBox(height: 16),
        _section('Executive summary'),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: <pw.Widget>[
            for (int i = 0; i < cards.length; i++) ...<pw.Widget>[
              if (i > 0) pw.SizedBox(width: 8),
              pw.Expanded(
                child: _kpiCard(cards[i].$1, cards[i].$2, highlight: i == 0),
              ),
            ],
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: const pw.BoxDecoration(
            color: _band,
            border: pw.Border(left: pw.BorderSide(color: _accent, width: 2)),
          ),
          child: pw.Text(
            pdfSafeText(salesNarrative(report, previous, audience)),
            style: const pw.TextStyle(
              fontSize: 8.5,
              color: _text,
              lineSpacing: 2,
            ),
          ),
        ),
        pw.SizedBox(height: 18),
        _section(
          '${salesHeadlineName(audience)} per ${salesRowNoun(report, plural: false)}',
          trailing: _legend(<(PdfColor, String)>[
            (_ink, 'This period'),
            if (previous != null) (_previous, 'Prior period'),
          ], dashed: daily ? 'Daily average' : 'Monthly average'),
        ),
        _trendChart(report: report, previous: previous, audience: audience),
        pw.SizedBox(height: 18),
        _insightPanels(report, audience),
        pw.SizedBox(height: 18),
        // Kept on one page: a comparison split across pages is hard to read.
        if (previous != null) ...<pw.Widget>[
          pw.Inseparable(
            child: pw.Column(
              children: <pw.Widget>[
                _section(
                  'Period comparison',
                  trailing: pw.Text(
                    '${report.coveredLabel}  vs  ${previous.coveredLabel}',
                    style: const pw.TextStyle(fontSize: 7.5, color: _muted),
                  ),
                ),
                _comparisonTable(metrics),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
        ],
        _section(
          daily ? 'Daily breakdown' : 'Monthly breakdown',
          trailing: pw.Text(
            'Amounts in Philippine pesos (PHP)',
            style: const pw.TextStyle(fontSize: 7.5, color: _muted),
          ),
        ),
        _breakdownTable(report, previous, audience),
        pw.SizedBox(height: 12),
        // Notes and sign-off stay together.
        pw.Inseparable(
          child: pw.Column(
            children: <pw.Widget>[
              _notes(owner),
              pw.SizedBox(height: 36),
              pw.Row(
                children: <pw.Widget>[
                  _signatureLine('Prepared by', preparedBy),
                  pw.SizedBox(width: 36),
                  _signatureLine('Checked by', ''),
                  pw.SizedBox(width: 36),
                  _signatureLine('Date', ''),
                ],
              ),
            ],
          ),
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
  SalesReport? previous,
}) {
  return Printing.layoutPdf(
    name: salesReportFileName(report, audience),
    onLayout: (PdfPageFormat format) => buildSalesReportPdf(
      report: report,
      audience: audience,
      scopeLabel: scopeLabel,
      preparedBy: preparedBy,
      previous: previous,
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
  SalesReport? previous,
}) async {
  final Uint8List bytes = await buildSalesReportPdf(
    report: report,
    audience: audience,
    scopeLabel: scopeLabel,
    preparedBy: preparedBy,
    previous: previous,
  );
  await Printing.sharePdf(
    bytes: bytes,
    filename: salesReportFileName(report, audience),
  );
}

// ---------------------------------------------------------------------------
// Building blocks

pw.Widget _titleBlock({
  required String title,
  required String scopeLabel,
  required SalesReport report,
  required SalesReport? previous,
  required String preparedBy,
  required String generated,
}) {
  pw.Widget meta(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: <pw.Widget>[
        pw.SizedBox(
          width: 62,
          child: pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 6.5,
              letterSpacing: 0.6,
              color: _onInkMuted,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        pw.Text(value, style: const pw.TextStyle(fontSize: 8, color: _onInk)),
      ],
    ),
  );

  return pw.Column(
    children: <pw.Widget>[
      pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(18, 16, 18, 14),
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
                        width: 14,
                        height: 14,
                        alignment: pw.Alignment.center,
                        decoration: const pw.BoxDecoration(
                          color: _accent,
                          borderRadius: pw.BorderRadius.all(
                            pw.Radius.circular(3),
                          ),
                        ),
                        child: pw.Text(
                          'P',
                          style: pw.TextStyle(
                            fontSize: 9,
                            fontWeight: pw.FontWeight.bold,
                            color: _ink,
                          ),
                        ),
                      ),
                      pw.SizedBox(width: 6),
                      pw.Text(
                        'SMARTPARK',
                        style: pw.TextStyle(
                          fontSize: 9,
                          letterSpacing: 1.5,
                          fontWeight: pw.FontWeight.bold,
                          color: _accent,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 10),
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: _onInk,
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    scopeLabel,
                    style: const pw.TextStyle(fontSize: 10, color: _onInkMuted),
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                meta('Period', salesReportPeriod(report)),
                if (report.isPartial) meta('Covers', report.coveredLabel),
                if (previous != null)
                  meta('Compared to', previous.coveredLabel),
                meta('Generated', generated),
                if (preparedBy.isNotEmpty) meta('Prepared by', preparedBy),
              ],
            ),
          ],
        ),
      ),
      pw.Container(height: 3, color: _accent),
    ],
  );
}

/// A section heading: small caps with a yellow tick, a rule, and optional
/// trailing content (a legend or note).
pw.Widget _section(String title, {pw.Widget? trailing}) => pw.Container(
  margin: const pw.EdgeInsets.only(bottom: 8),
  padding: const pw.EdgeInsets.only(bottom: 4),
  decoration: const pw.BoxDecoration(
    border: pw.Border(bottom: pw.BorderSide(color: _rule, width: 0.6)),
  ),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.end,
    children: <pw.Widget>[
      pw.Container(width: 3, height: 10, color: _accent),
      pw.SizedBox(width: 6),
      pw.Expanded(
        child: pw.Text(
          title.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 8.5,
            letterSpacing: 0.8,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
      ),
      ?trailing,
    ],
  ),
);

PdfColor _changeColor(SalesMetric m) {
  final double? r = m.ratio;
  if (m.neutral || r == null || r.abs() < 0.0005) return _muted;
  return r > 0 ? _up : _down;
}

pw.Widget _kpiCard(String label, SalesMetric m, {bool highlight = false}) {
  final double? r = m.ratio;
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(9, 8, 9, 8),
    decoration: pw.BoxDecoration(
      color: highlight ? _accentSoft : null,
      border: pw.Border.all(color: highlight ? _accent : _rule, width: 0.6),
      borderRadius: pw.BorderRadius.circular(3),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: <pw.Widget>[
        pw.Text(
          label.toUpperCase(),
          maxLines: 1,
          style: pw.TextStyle(
            fontSize: 6.5,
            letterSpacing: 0.5,
            fontWeight: pw.FontWeight.bold,
            color: _muted,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          formatSalesValue(m.current, m.unit),
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
            color: _ink,
          ),
        ),
        pw.SizedBox(height: 4),
        if (m.previous == null)
          pw.Text(
            'No comparison',
            style: const pw.TextStyle(fontSize: 7, color: _muted),
          )
        else
          pw.RichText(
            text: pw.TextSpan(
              children: <pw.InlineSpan>[
                pw.TextSpan(
                  // No base to compare against: "New" when there is
                  // something now, otherwise nothing changed.
                  text: r != null
                      ? formatSalesChange(r)
                      : m.current == 0
                      ? 'No change'
                      : 'New',
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    fontWeight: pw.FontWeight.bold,
                    color: r == null ? _muted : _changeColor(m),
                  ),
                ),
                pw.TextSpan(
                  text: '  vs ${formatSalesValue(m.previous!, m.unit)}',
                  style: const pw.TextStyle(fontSize: 7, color: _muted),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

pw.Widget _legend(List<(PdfColor, String)> items, {String? dashed}) {
  pw.Widget label(String text) =>
      pw.Text(text, style: const pw.TextStyle(fontSize: 7, color: _muted));
  return pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    children: <pw.Widget>[
      for (final (PdfColor color, String text) in items) ...<pw.Widget>[
        pw.Container(width: 7, height: 7, color: color),
        pw.SizedBox(width: 3),
        label(text),
        pw.SizedBox(width: 10),
      ],
      if (dashed != null) ...<pw.Widget>[
        pw.CustomPaint(
          size: const PdfPoint(14, 7),
          painter: (PdfGraphics canvas, PdfPoint size) {
            canvas
              ..setStrokeColor(_accent)
              ..setLineWidth(1.2)
              ..setLineDashPattern(<num>[2.5, 1.5])
              ..drawLine(0, size.y / 2, size.x, size.y / 2)
              ..strokePath();
          },
        ),
        pw.SizedBox(width: 3),
        label(dashed),
      ],
    ],
  );
}

/// A round axis top (1, 2, 2.5 or 5 times a power of ten) at or above [max].
double _niceStep(double max, int ticks) {
  if (max <= 0) return 1;
  final double raw = max / ticks;
  final double magnitude = math
      .pow(10, (math.log(raw) / math.ln10).floor())
      .toDouble();
  for (final double f in <double>[1, 2, 2.5, 5, 10]) {
    if (f * magnitude >= raw) return f * magnitude;
  }
  return 10 * magnitude;
}

/// "850", "1.2k", "15k", "1.5M".
String _compact(double pesos) {
  if (pesos >= 1e6) return '${_trim(pesos / 1e6)}M';
  if (pesos >= 1e3) return '${_trim(pesos / 1e3)}k';
  return _trim(pesos);
}

String _trim(double v) {
  final String s = v.toStringAsFixed(
    v >= 100 || v == v.roundToDouble() ? 0 : 1,
  );
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

/// Bars per day or month, this period beside the prior one, with the
/// average as a dashed line.
pw.Widget _trendChart({
  required SalesReport report,
  required SalesReport? previous,
  required SalesReportAudience audience,
}) {
  const double height = 128;
  const double axisWidth = 40;
  const int ticks = 4;
  final bool daily = report.breakdown == SalesBreakdown.daily;
  final List<double> current = <double>[
    for (final SalesRow r in report.rows) salesHeadline(r, audience) / 100,
  ];
  final List<double>? prior = previous == null
      ? null
      : <double>[
          for (final SalesRow r in previous.rows)
            salesHeadline(r, audience) / 100,
        ];
  // One slot per day or month of the whole range, so a period still
  // running shows how far along it is.
  final FinanceRange range = report.range;
  final int whole = daily
      ? DateTime.utc(range.lastDay.year, range.lastDay.month, range.lastDay.day)
                .difference(
                  DateTime.utc(
                    range.start.year,
                    range.start.month,
                    range.start.day,
                  ),
                )
                .inDays +
            1
      : (range.lastDay.year - range.start.year) * 12 +
            range.lastDay.month -
            range.start.month +
            1;
  final int slots = <int>[
    whole,
    current.length,
    prior?.length ?? 0,
  ].reduce(math.max);
  if (slots == 0) {
    return pw.SizedBox(height: 20);
  }
  final double top = <double>[...current, ...?prior].fold<double>(0, math.max);
  final double step = _niceStep(top, ticks);
  final double scaleMax = step * ticks;
  final double average = current.isEmpty
      ? 0
      : current.reduce((double a, double b) => a + b) / current.length;

  // Labels: day of month ("1".."31"), weekday + day for weeks, or month.
  String labelFor(int i) {
    final DateTime start = i < report.rows.length
        ? report.rows[i].start
        : (daily
              ? DateTime(
                  report.range.start.year,
                  report.range.start.month,
                  report.range.start.day + i,
                )
              : DateTime(
                  report.range.start.year,
                  report.range.start.month + i,
                ));
    if (!daily) return kSalesMonthNames[start.month - 1].substring(0, 3);
    if (report.range.period == FinancePeriod.week) {
      return '${salesWeekday(start)} ${start.day}';
    }
    return '${start.day}';
  }

  final int every = (slots / 16).ceil();

  return pw.Column(
    children: <pw.Widget>[
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.SizedBox(
            width: axisWidth,
            height: height,
            child: pw.Stack(
              overflow: pw.Overflow.visible,
              children: <pw.Widget>[
                for (int t = 0; t <= ticks; t++)
                  pw.Positioned(
                    right: 5,
                    bottom: height * t / ticks - 3.5,
                    child: pw.Text(
                      _compact(step * t),
                      style: const pw.TextStyle(fontSize: 6.5, color: _muted),
                    ),
                  ),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.SizedBox(
              height: height,
              child: pw.CustomPaint(
                painter: (PdfGraphics canvas, PdfPoint size) {
                  // Grid.
                  canvas
                    ..setStrokeColor(_rule)
                    ..setLineWidth(0.4);
                  for (int t = 1; t <= ticks; t++) {
                    final double y = size.y * t / ticks;
                    canvas.drawLine(0, y, size.x, y);
                  }
                  canvas.strokePath();
                  canvas
                    ..setStrokeColor(_muted)
                    ..setLineWidth(0.6)
                    ..drawLine(0, 0, size.x, 0)
                    ..strokePath();

                  final double slot = size.x / slots;
                  final bool paired = prior != null;
                  final double bar = math.min(
                    paired ? slot * 0.36 : slot * 0.6,
                    28,
                  );
                  final double gap = paired ? math.min(slot * 0.06, 2) : 0;
                  double h(double v) =>
                      scaleMax == 0 ? 0 : size.y * v / scaleMax;
                  for (int i = 0; i < slots; i++) {
                    final double centre = slot * (i + 0.5);
                    if (paired && i < prior.length && prior[i] > 0) {
                      canvas
                        ..setFillColor(_previous)
                        ..drawRect(centre - gap / 2 - bar, 0, bar, h(prior[i]))
                        ..fillPath();
                    }
                    if (i < current.length && current[i] > 0) {
                      canvas
                        ..setFillColor(_ink)
                        ..drawRect(
                          paired ? centre + gap / 2 : centre - bar / 2,
                          0,
                          bar,
                          h(current[i]),
                        )
                        ..fillPath();
                    }
                  }
                  if (average > 0) {
                    canvas
                      ..setStrokeColor(_accent)
                      ..setLineWidth(1.2)
                      ..setLineDashPattern(<num>[3, 2])
                      ..drawLine(0, h(average), size.x, h(average))
                      ..strokePath()
                      ..setLineDashPattern();
                  }
                },
              ),
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 3),
      pw.Row(
        children: <pw.Widget>[
          pw.SizedBox(
            width: axisWidth,
            child: pw.Text(
              'PHP',
              style: const pw.TextStyle(fontSize: 6.5, color: _muted),
            ),
          ),
          for (int i = 0; i < slots; i++)
            pw.Expanded(
              child: pw.Text(
                i % every == 0 ? labelFor(i) : '',
                textAlign: pw.TextAlign.center,
                maxLines: 1,
                style: pw.TextStyle(
                  fontSize: 6.5,
                  color: i < report.rows.length ? _text : _muted,
                ),
              ),
            ),
        ],
      ),
    ],
  );
}

/// Two panels under the chart: the average per weekday (daily reports
/// longer than a week) or the top rows, beside where each peso went (owner)
/// or the busiest rows by transactions (admin).
pw.Widget _insightPanels(SalesReport report, SalesReportAudience audience) {
  final bool owner = audience == SalesReportAudience.owner;
  final bool daily = report.breakdown == SalesBreakdown.daily;
  final String rows = daily ? 'days' : 'months';
  final pw.Widget left = daily && report.rows.length > 7
      ? _weekdayPanel(report, audience)
      : _topRowsPanel(
          report,
          'Top $rows by ${salesHeadlineName(audience).toLowerCase()}',
          (SalesRow r) => salesHeadline(r, audience),
          money: true,
        );
  final pw.Widget right = owner
      ? _moneyPanel(report.totals)
      : _topRowsPanel(
          report,
          'Top $rows by transactions',
          (SalesRow r) => r.count,
          money: false,
        );
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.Expanded(child: left),
      pw.SizedBox(width: 20),
      pw.Expanded(child: right),
    ],
  );
}

pw.Widget _panelTitle(String text) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 6),
  child: pw.Text(
    text.toUpperCase(),
    style: pw.TextStyle(
      fontSize: 7.5,
      letterSpacing: 0.6,
      fontWeight: pw.FontWeight.bold,
      color: _ink,
    ),
  ),
);

/// A labelled horizontal bar, [value] out of [max].
pw.Widget _hBar(
  String label,
  double fraction,
  String value, {
  PdfColor color = _ink,
}) {
  final int filled = (fraction.clamp(0, 1) * 1000).round();
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      children: <pw.Widget>[
        pw.SizedBox(
          width: 44,
          child: pw.Text(
            label,
            maxLines: 1,
            style: const pw.TextStyle(fontSize: 7.5, color: _text),
          ),
        ),
        pw.Expanded(
          child: pw.Container(
            height: 8,
            color: _band,
            child: pw.Row(
              children: <pw.Widget>[
                if (filled > 0)
                  pw.Expanded(
                    flex: filled,
                    child: pw.Container(color: color),
                  ),
                if (filled < 1000)
                  pw.Expanded(flex: 1000 - filled, child: pw.SizedBox()),
              ],
            ),
          ),
        ),
        pw.SizedBox(
          width: 62,
          child: pw.Text(
            value,
            textAlign: pw.TextAlign.right,
            style: const pw.TextStyle(fontSize: 7.5, color: _text),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _weekdayPanel(SalesReport report, SalesReportAudience audience) {
  final ({List<int> totals, List<int> days}) w = salesByWeekday(
    report,
    audience,
  );
  final List<double> avg = <double>[
    for (int i = 0; i < 7; i++) w.days[i] == 0 ? 0 : w.totals[i] / w.days[i],
  ];
  final double max = avg.fold<double>(0, math.max);
  final int best = max == 0 ? -1 : avg.indexOf(max);
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      _panelTitle('Average by day of week'),
      for (int i = 0; i < 7; i++)
        _hBar(
          kSalesWeekdays[i],
          max == 0 ? 0 : avg[i] / max,
          formatSalesPeso((avg[i]).round()).replaceFirst('PHP ', ''),
          color: i == best ? _accent : _ink,
        ),
      pw.SizedBox(height: 4),
      pw.Text(
        best < 0
            ? 'No activity yet.'
            : 'Busiest: ${kSalesWeekdays[best]}, averaging '
                  '${formatSalesPeso(max.round())} a day.',
        style: const pw.TextStyle(fontSize: 7, color: _muted),
      ),
    ],
  );
}

pw.Widget _moneyPanel(SalesRow t) {
  final int gross = t.grossCentavos;
  double share(int part) => gross == 0 ? 0 : part / gross;
  String pct(int part) =>
      gross == 0 ? '-' : '${(share(part) * 100).toStringAsFixed(1)}%';
  const PdfColor fees = PdfColor.fromInt(0xFF8E939E);
  final List<(String, int, PdfColor)> parts = <(String, int, PdfColor)>[
    ('Payout to you (est.)', t.payoutCentavos, _ink),
    ('SmartPark commission', t.commissionCentavos, _accent),
    ('Processing fee (est.)', t.processingCentavos, fees),
  ];
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      _panelTitle('Where gross sales went'),
      pw.Container(
        height: 12,
        color: _band,
        child: gross == 0
            ? pw.SizedBox()
            : pw.Row(
                children: <pw.Widget>[
                  for (final (String _, int amount, PdfColor color) in parts)
                    if (amount > 0)
                      pw.Expanded(
                        flex: math.max(1, (share(amount) * 1000).round()),
                        child: pw.Container(color: color),
                      ),
                ],
              ),
      ),
      pw.SizedBox(height: 6),
      for (final (String label, int amount, PdfColor color) in parts)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
          child: pw.Row(
            children: <pw.Widget>[
              pw.Container(width: 6, height: 6, color: color),
              pw.SizedBox(width: 5),
              pw.Expanded(
                child: pw.Text(
                  label,
                  style: const pw.TextStyle(fontSize: 7.5, color: _text),
                ),
              ),
              pw.SizedBox(
                width: 34,
                child: pw.Text(
                  pct(amount),
                  textAlign: pw.TextAlign.right,
                  style: const pw.TextStyle(fontSize: 7.5, color: _muted),
                ),
              ),
              pw.SizedBox(
                width: 64,
                child: pw.Text(
                  formatSalesPeso(amount).replaceFirst('PHP ', ''),
                  textAlign: pw.TextAlign.right,
                  style: const pw.TextStyle(fontSize: 7.5, color: _text),
                ),
              ),
            ],
          ),
        ),
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 4),
        padding: const pw.EdgeInsets.only(top: 4),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _rule, width: 0.5)),
        ),
        child: pw.Row(
          children: <pw.Widget>[
            pw.Expanded(
              child: pw.Text(
                'Plus overtime cash collected at the gate',
                style: const pw.TextStyle(fontSize: 7.5, color: _text),
              ),
            ),
            pw.Text(
              formatSalesPeso(t.cashCentavos).replaceFirst('PHP ', ''),
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: _text,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// The five best rows by [value], as bars.
pw.Widget _topRowsPanel(
  SalesReport report,
  String title,
  int Function(SalesRow) value, {
  required bool money,
}) {
  final List<SalesRow> ranked =
      report.rows.where((SalesRow r) => value(r) > 0).toList()
        ..sort((SalesRow a, SalesRow b) => value(b).compareTo(value(a)));
  final int max = ranked.isEmpty ? 0 : value(ranked.first);
  final bool daily = report.breakdown == SalesBreakdown.daily;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      _panelTitle(title),
      if (ranked.isEmpty)
        pw.Text(
          'No activity yet.',
          style: const pw.TextStyle(fontSize: 7.5, color: _muted),
        ),
      for (int i = 0; i < math.min(5, ranked.length); i++)
        _hBar(
          daily
              ? '${salesWeekday(ranked[i].start)} ${ranked[i].start.day}'
              : report.rowLabel(ranked[i]).substring(0, 3),
          value(ranked[i]) / max,
          money
              ? formatSalesPeso(value(ranked[i])).replaceFirst('PHP ', '')
              : '${value(ranked[i])}',
          color: i == 0 ? _accent : _ink,
        ),
    ],
  );
}

pw.Widget _comparisonTable(List<SalesMetric> metrics) {
  final List<List<String>> data = <List<String>>[
    for (final SalesMetric m in metrics)
      <String>[
        m.label,
        formatSalesValue(m.current, m.unit),
        formatSalesValue(m.previous ?? 0, m.unit),
        m.change == null
            ? '-'
            : '${m.change! > 0 ? '+' : ''}'
                  '${formatSalesValue(m.change!, m.unit)}',
        formatSalesChange(m.ratio),
      ],
  ];
  return pw.TableHelper.fromTextArray(
    headers: const <String>[
      'Metric',
      'This period',
      'Prior period',
      'Change',
      '% Change',
    ],
    data: data,
    columnWidths: const <int, pw.TableColumnWidth>{
      0: pw.FlexColumnWidth(2.4),
      1: pw.FlexColumnWidth(1.5),
      2: pw.FlexColumnWidth(1.5),
      3: pw.FlexColumnWidth(1.5),
      4: pw.FlexColumnWidth(1),
    },
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _rule, width: 0.4),
      bottom: pw.BorderSide(color: _ink, width: 0.8),
    ),
    headerStyle: pw.TextStyle(
      fontSize: 7.5,
      fontWeight: pw.FontWeight.bold,
      color: _onInk,
    ),
    headerDecoration: const pw.BoxDecoration(color: _ink),
    cellStyle: const pw.TextStyle(fontSize: 8, color: _text),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
    cellAlignment: pw.Alignment.centerRight,
    cellAlignments: const <int, pw.Alignment>{0: pw.Alignment.centerLeft},
    headerAlignment: pw.Alignment.centerRight,
    headerAlignments: const <int, pw.Alignment>{0: pw.Alignment.centerLeft},
    oddRowDecoration: const pw.BoxDecoration(color: _band),
    textStyleBuilder: (int column, dynamic value, int rowNum) {
      if (rowNum == 0) return null;
      final SalesMetric m = metrics[rowNum - 1];
      if (column == 0 && rowNum == 1) {
        return pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: _ink,
        );
      }
      if (column >= 3) {
        return pw.TextStyle(
          fontSize: 8,
          fontWeight: column == 4 ? pw.FontWeight.bold : null,
          color: _changeColor(m),
        );
      }
      return null;
    },
  );
}

pw.Widget _breakdownTable(
  SalesReport report,
  SalesReport? previous,
  SalesReportAudience audience,
) {
  final bool owner = audience == SalesReportAudience.owner;
  final bool daily = report.breakdown == SalesBreakdown.daily;
  final int headlineTotal = salesHeadline(report.totals, audience);
  String amount(int c) => formatSalesPeso(c).replaceFirst('PHP ', '');
  String share(int c) => headlineTotal == 0
      ? '-'
      : '${(c * 100 / headlineTotal).toStringAsFixed(1)}%';

  final List<String> headers = <String>[
    daily ? 'Date' : 'Month',
    'Txns',
    if (owner) ...<String>[
      'Gross sales',
      'Share',
      'Commission',
      'Processing',
      'Payout (est.)',
      'OT cash',
    ] else ...<String>[
      'Commission',
      'Share',
      'Per txn',
      if (previous != null) ...<String>['Prior period', 'Change'],
    ],
  ];

  List<String> cells(String label, SalesRow r, {SalesRow? prior}) {
    final int head = salesHeadline(r, audience);
    return <String>[
      label,
      '${r.count}',
      if (owner) ...<String>[
        amount(r.grossCentavos),
        share(r.grossCentavos),
        amount(r.commissionCentavos),
        amount(r.processingCentavos),
        amount(r.payoutCentavos),
        amount(r.cashCentavos),
      ] else ...<String>[
        amount(r.commissionCentavos),
        share(r.commissionCentavos),
        r.count == 0 ? '-' : amount((r.commissionCentavos / r.count).round()),
        if (previous != null) ...<String>[
          prior == null ? '-' : amount(salesHeadline(prior, audience)),
          prior == null
              ? '-'
              : formatSalesChange(
                  salesChange(head, salesHeadline(prior, audience)),
                ),
        ],
      ],
    ];
  }

  final List<SalesRow> rows = report.rows;
  final List<List<String>> data = <List<String>>[
    for (int i = 0; i < rows.length; i++)
      cells(
        daily
            ? '${salesWeekday(rows[i].start)}, ${report.rowLabel(rows[i])}'
            : '${report.rowLabel(rows[i])} ${rows[i].start.year}',
        rows[i],
        prior: previous != null && i < previous.rows.length
            ? previous.rows[i]
            : null,
      ),
  ];
  final SalesRow average = SalesRow(report.range.start);
  if (rows.isNotEmpty) {
    final int n = rows.length;
    average
      ..count = (report.totals.count / n).round()
      ..grossCentavos = (report.totals.grossCentavos / n).round()
      ..commissionCentavos = (report.totals.commissionCentavos / n).round()
      ..processingCentavos = (report.totals.processingCentavos / n).round()
      ..payoutCentavos = (report.totals.payoutCentavos / n).round()
      ..cashCentavos = (report.totals.cashCentavos / n).round();
  }
  final List<String> averageCells = cells(
    'Average per ${salesRowNoun(report, plural: false)}',
    average,
  );
  if (rows.isNotEmpty) {
    averageCells[1] = (report.totals.count / rows.length).toStringAsFixed(1);
  }
  // The average's share and per-row comparison mean little; blank them.
  for (int c = 0; c < headers.length; c++) {
    if (headers[c] == 'Share' || headers[c] == 'Change') averageCells[c] = '';
    if (headers[c] == 'Prior period') averageCells[c] = '';
  }
  final List<String> totalCells = cells(
    'Total',
    report.totals,
    prior: previous?.totals,
  );
  final int totalRow = data.length + 1;
  final int averageRow = data.length + 2;

  return pw.TableHelper.fromTextArray(
    headers: headers,
    data: <List<String>>[...data, totalCells, averageCells],
    headerCount: 1,
    columnWidths: <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(1.6),
      1: const pw.FlexColumnWidth(0.6),
      for (int c = 2; c < headers.length; c++)
        c: pw.FlexColumnWidth(headers[c] == 'Share' ? 0.75 : 1.2),
    },
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _rule, width: 0.4),
    ),
    headerStyle: pw.TextStyle(
      fontSize: 7.5,
      fontWeight: pw.FontWeight.bold,
      color: _onInk,
    ),
    headerDecoration: const pw.BoxDecoration(color: _ink),
    cellStyle: const pw.TextStyle(fontSize: 7.5, color: _text),
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.2),
    cellAlignment: pw.Alignment.centerRight,
    cellAlignments: const <int, pw.Alignment>{0: pw.Alignment.centerLeft},
    headerAlignment: pw.Alignment.centerRight,
    headerAlignments: const <int, pw.Alignment>{0: pw.Alignment.centerLeft},
    cellDecoration: (int index, dynamic value, int rowNum) {
      if (rowNum == totalRow) {
        return const pw.BoxDecoration(
          color: _accentSoft,
          border: pw.Border(top: pw.BorderSide(color: _ink, width: 0.8)),
        );
      }
      if (rowNum == averageRow) {
        return const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 0.8)),
        );
      }
      return rowNum.isEven
          ? const pw.BoxDecoration(color: _band)
          : const pw.BoxDecoration();
    },
    textStyleBuilder: (int column, dynamic value, int rowNum) {
      if (rowNum == totalRow) {
        return pw.TextStyle(
          fontSize: 7.5,
          fontWeight: pw.FontWeight.bold,
          color: _ink,
        );
      }
      if (rowNum == averageRow) {
        return pw.TextStyle(
          fontSize: 7.5,
          fontStyle: pw.FontStyle.italic,
          color: _muted,
        );
      }
      if (rowNum > 0 && rowNum <= rows.length && rows[rowNum - 1].isEmpty) {
        return const pw.TextStyle(fontSize: 7.5, color: _muted);
      }
      if (headers[column] == 'Change' && value is String) {
        return pw.TextStyle(
          fontSize: 7.5,
          color: value.startsWith('+')
              ? _up
              : value.startsWith('-') && value.length > 1
              ? _down
              : _muted,
        );
      }
      return null;
    },
  );
}

pw.Widget _notes(bool owner) {
  final List<String> notes = <String>[
    if (owner) ...<String>[
      'Gross sales are in-app payments for paid tickets. Commission is '
          "SmartPark's platform fee.",
      "Processing is an estimate of PayMongo's fee, so the payout is an "
          "estimate too; PayMongo's settlement report has the exact amounts.",
      'Overtime cash is collected at the gate, outside the app, and counted '
          'on the day it was collected.',
    ] else
      "Commission is SmartPark's platform fee on in-app parking payments, "
          'across all facilities.',
    'The prior period is the one before this, cut at the same point while '
        'this one is still running. "n/a" means there is nothing to compare '
        'against.',
  ];
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.Text(
        'NOTES',
        style: pw.TextStyle(
          fontSize: 7,
          letterSpacing: 0.6,
          fontWeight: pw.FontWeight.bold,
          color: _muted,
        ),
      ),
      pw.SizedBox(height: 3),
      for (int i = 0; i < notes.length; i++)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.SizedBox(
                width: 10,
                child: pw.Text(
                  '${i + 1}.',
                  style: const pw.TextStyle(fontSize: 7, color: _muted),
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  notes[i],
                  style: const pw.TextStyle(fontSize: 7, color: _muted),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

pw.Widget _signatureLine(String label, String name) => pw.Expanded(
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.SizedBox(
        height: 12,
        child: pw.Text(
          name,
          style: const pw.TextStyle(fontSize: 8, color: _text),
        ),
      ),
      pw.Container(
        height: 0.6,
        color: _ink,
        margin: const pw.EdgeInsets.only(top: 2, bottom: 3),
      ),
      pw.Text(
        label.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 6.5,
          letterSpacing: 0.6,
          fontWeight: pw.FontWeight.bold,
          color: _muted,
        ),
      ),
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
