/// The sales report as an Excel workbook (.xlsx): a Summary sheet (key
/// figures, the comparison with the prior period, insights and a chart) and
/// a Breakdown sheet with one row per day or month.
///
/// The workbook is written as plain Office Open XML, so it needs no
/// spreadsheet package and can carry a native Excel chart. Totals, shares
/// and changes are live formulas, with their values cached so previewers
/// that don't calculate still show them.
library;

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:archive/archive.dart';
import 'package:share_plus/share_plus.dart';

import 'sales_report.dart';
import 'sales_report_summary.dart';

const String kXlsxMimeType =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Opens the share sheet with the report as an Excel file. On iPad,
/// [origin] is where the share popover points.
Future<void> shareSalesReportExcel({
  required SalesReport report,
  required SalesReportAudience audience,
  required String scopeLabel,
  required String preparedBy,
  SalesReport? previous,
  Rect? origin,
}) async {
  final Uint8List bytes = buildSalesReportXlsx(
    report: report,
    previous: previous,
    audience: audience,
    scopeLabel: scopeLabel,
    preparedBy: preparedBy,
  );
  final String name = salesReportFileName(report, audience, extension: 'xlsx');
  await SharePlus.instance.share(
    ShareParams(
      files: <XFile>[
        XFile.fromData(bytes, mimeType: kXlsxMimeType, name: name),
      ],
      fileNameOverrides: <String>[name],
      subject:
          '${salesReportTitle(report, audience)} - '
          '${salesReportPeriod(report)}',
      sharePositionOrigin: origin,
    ),
  );
}

/// Builds the workbook bytes.
Uint8List buildSalesReportXlsx({
  required SalesReport report,
  required SalesReportAudience audience,
  required String scopeLabel,
  required String preparedBy,
  SalesReport? previous,
  DateTime? generatedAt,
}) {
  final DateTime now = generatedAt ?? DateTime.now();
  final _Breakdown breakdown = _Breakdown(report, previous, audience);
  final _SheetXml breakdownSheet = breakdown.build(scopeLabel);
  final _Summary summary = _Summary(
    report: report,
    previous: previous,
    audience: audience,
    scopeLabel: scopeLabel,
    preparedBy: preparedBy,
    generated: now,
  );
  final _SheetXml summarySheet = summary.build();
  final String chart = _chartXml(report, previous, audience, breakdown);
  final String title =
      '${salesReportTitle(report, audience)} - ${salesReportPeriod(report)}';

  final Archive archive = Archive();
  void add(String path, String xml) =>
      archive.addFile(ArchiveFile.bytes(path, utf8.encode(xml)));

  add('[Content_Types].xml', _contentTypes);
  add('_rels/.rels', _rootRels);
  add('docProps/app.xml', _appXml);
  add('docProps/core.xml', _coreXml(title, preparedBy, now));
  add('xl/workbook.xml', _workbookXml(breakdown));
  add('xl/_rels/workbook.xml.rels', _workbookRels);
  add('xl/styles.xml', _stylesXml);
  add('xl/worksheets/sheet1.xml', summarySheet.xml);
  add('xl/worksheets/_rels/sheet1.xml.rels', _sheetDrawingRels);
  add('xl/worksheets/sheet2.xml', breakdownSheet.xml);
  add(
    'xl/drawings/drawing1.xml',
    _drawingXml(summary.chartRow, summary.chartRow + 20),
  );
  add('xl/drawings/_rels/drawing1.xml.rels', _drawingRels);
  add('xl/charts/chart1.xml', chart);

  return Uint8List.fromList(ZipEncoder().encodeBytes(archive));
}

// ---------------------------------------------------------------------------
// Styles. The indexes below match cellXfs in [_stylesXml].

abstract final class _S {
  static const int title = 1;
  static const int brand = 2;
  static const int muted = 3;
  static const int section = 4;
  static const int header = 5;
  static const int headerRight = 6;
  static const int text = 7;
  static const int money = 8;
  static const int integer = 9;
  static const int change = 10;
  static const int moneyChange = 11;
  static const int intChange = 12;
  static const int date = 13;
  static const int month = 14;
  static const int share = 15;
  static const int totalText = 16;
  static const int totalMoney = 17;
  static const int totalInt = 18;
  static const int totalShare = 19;
  static const int totalChange = 20;
  static const int avgText = 21;
  static const int avgMoney = 22;
  static const int avgDecimal = 23;
  static const int metaLabel = 24;
  static const int metaValue = 25;
  static const int textBold = 26;
  static const int kpiLabel = 28;
  static const int kpiMoney = 29;
  static const int kpiInt = 30;
  static const int kpiChange = 31;
  static const int kpiText = 32;
  static const int textMutedRow = 33;
  static const int narrative = 34;
}

const String _stylesXml = '''
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
<numFmts count="7">
<numFmt numFmtId="164" formatCode="[Color10]+0.0%;[Red]\\-0.0%;0.0%"/>
<numFmt numFmtId="165" formatCode="+#,##0.00;\\-#,##0.00;0.00"/>
<numFmt numFmtId="166" formatCode="+#,##0;\\-#,##0;0"/>
<numFmt numFmtId="167" formatCode="mmm d, yyyy"/>
<numFmt numFmtId="168" formatCode="mmmm yyyy"/>
<numFmt numFmtId="169" formatCode="0.0%"/>
<numFmt numFmtId="170" formatCode="#,##0.0"/>
</numFmts>
<fonts count="10">
<font><sz val="10"/><color rgb="FF2B2F38"/><name val="Arial"/><family val="2"/></font>
<font><b/><sz val="10"/><color rgb="FF1F2128"/><name val="Arial"/><family val="2"/></font>
<font><b/><sz val="18"/><color rgb="FF1F2128"/><name val="Arial"/><family val="2"/></font>
<font><b/><sz val="10"/><color rgb="FFFFFFFF"/><name val="Arial"/><family val="2"/></font>
<font><sz val="9"/><color rgb="FF6B7080"/><name val="Arial"/><family val="2"/></font>
<font><b/><sz val="9"/><color rgb="FF8A6A0C"/><name val="Arial"/><family val="2"/></font>
<font><i/><sz val="10"/><color rgb="FF6B7080"/><name val="Arial"/><family val="2"/></font>
<font><b/><sz val="11"/><color rgb="FF1F2128"/><name val="Arial"/><family val="2"/></font>
<font><b/><sz val="8"/><color rgb="FF6B7080"/><name val="Arial"/><family val="2"/></font>
<font><b/><sz val="14"/><color rgb="FF1F2128"/><name val="Arial"/><family val="2"/></font>
</fonts>
<fills count="6">
<fill><patternFill patternType="none"/></fill>
<fill><patternFill patternType="gray125"/></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FF1F2128"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFF4F5F7"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFFFF4CF"/><bgColor indexed="64"/></patternFill></fill>
<fill><patternFill patternType="solid"><fgColor rgb="FFF2C335"/><bgColor indexed="64"/></patternFill></fill>
</fills>
<borders count="5">
<border><left/><right/><top/><bottom/><diagonal/></border>
<border><left/><right/><top/><bottom style="thin"><color rgb="FFDCDFE5"/></bottom><diagonal/></border>
<border><left/><right/><top style="thin"><color rgb="FF1F2128"/></top><bottom style="thin"><color rgb="FF1F2128"/></bottom><diagonal/></border>
<border><left/><right/><top/><bottom style="medium"><color rgb="FFF2C335"/></bottom><diagonal/></border>
<border><left/><right/><top/><bottom style="thin"><color rgb="FF1F2128"/></bottom><diagonal/></border>
</borders>
<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
<cellXfs count="35">
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="5" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="7" fillId="0" borderId="3" xfId="0" applyFont="1" applyBorder="1"/>
<xf numFmtId="0" fontId="3" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="center"/></xf>
<xf numFmtId="0" fontId="3" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>
<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>
<xf numFmtId="4" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>
<xf numFmtId="3" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>
<xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right"/></xf>
<xf numFmtId="165" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>
<xf numFmtId="166" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>
<xf numFmtId="167" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left"/></xf>
<xf numFmtId="168" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1" applyAlignment="1"><alignment horizontal="left"/></xf>
<xf numFmtId="169" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>
<xf numFmtId="0" fontId="1" fillId="4" borderId="2" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>
<xf numFmtId="4" fontId="1" fillId="4" borderId="2" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>
<xf numFmtId="3" fontId="1" fillId="4" borderId="2" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>
<xf numFmtId="169" fontId="1" fillId="4" borderId="2" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1"/>
<xf numFmtId="164" fontId="1" fillId="4" borderId="2" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment horizontal="right"/></xf>
<xf numFmtId="0" fontId="6" fillId="0" borderId="4" xfId="0" applyFont="1" applyBorder="1"/>
<xf numFmtId="4" fontId="6" fillId="0" borderId="4" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1"/>
<xf numFmtId="170" fontId="6" fillId="0" borderId="4" xfId="0" applyNumberFormat="1" applyFont="1" applyBorder="1"/>
<xf numFmtId="0" fontId="8" fillId="0" borderId="0" xfId="0" applyFont="1"/>
<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment horizontal="left"/></xf>
<xf numFmtId="0" fontId="1" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1"/>
<xf numFmtId="0" fontId="4" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
<xf numFmtId="0" fontId="8" fillId="3" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment vertical="bottom"/></xf>
<xf numFmtId="4" fontId="9" fillId="3" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="left"/></xf>
<xf numFmtId="3" fontId="9" fillId="3" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="left"/></xf>
<xf numFmtId="164" fontId="1" fillId="3" borderId="0" xfId="0" applyNumberFormat="1" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="left" vertical="top"/></xf>
<xf numFmtId="0" fontId="4" fillId="3" borderId="0" xfId="0" applyFont="1" applyFill="1" applyAlignment="1"><alignment horizontal="left" vertical="top"/></xf>
<xf numFmtId="0" fontId="4" fillId="0" borderId="1" xfId="0" applyFont="1" applyBorder="1"/>
<xf numFmtId="0" fontId="0" fillId="3" borderId="0" xfId="0" applyFill="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
</cellXfs>
<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>
''';

// ---------------------------------------------------------------------------
// Cells and sheets

String _col(int index) {
  // 0 -> A, 25 -> Z, 26 -> AA.
  String out = '';
  int n = index + 1;
  while (n > 0) {
    final int r = (n - 1) % 26;
    out = String.fromCharCode(65 + r) + out;
    n = (n - 1) ~/ 26;
  }
  return out;
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Excel's serial day number (days since Dec 30, 1899).
int _serial(DateTime d) => DateTime.utc(
  d.year,
  d.month,
  d.day,
).difference(DateTime.utc(1899, 12, 30)).inDays;

double _pesos(int centavos) => centavos / 100;

/// A value and how it's written: text, a number, or a formula with its
/// cached result (a number, text, or nothing).
class _Cell {
  const _Cell.text(this.text, this.style) : number = null, formula = null;
  const _Cell.number(this.number, this.style) : text = null, formula = null;
  const _Cell.formula(this.formula, this.style, {this.number, this.text});
  const _Cell.blank(this.style) : text = null, number = null, formula = null;

  final String? text;
  final num? number;
  final String? formula;
  final int style;

  String xml(String ref) {
    final String s = style == 0 ? '' : ' s="$style"';
    if (formula != null) {
      final String f = '<f>${_esc(formula!)}</f>';
      if (text != null) {
        return '<c r="$ref"$s t="str">$f<v>${_esc(text!)}</v></c>';
      }
      return '<c r="$ref"$s>$f${number == null ? '' : '<v>${_num(number!)}</v>'}</c>';
    }
    if (text != null) {
      return '<c r="$ref"$s t="inlineStr"><is><t xml:space="preserve">'
          '${_esc(text!)}</t></is></c>';
    }
    if (number != null) return '<c r="$ref"$s><v>${_num(number!)}</v></c>';
    return '<c r="$ref"$s/>';
  }

  static String _num(num n) {
    if (n is int) return '$n';
    final double d = n.toDouble();
    if (d.isNaN || d.isInfinite) return '0';
    return d == d.roundToDouble() ? d.toInt().toString() : d.toString();
  }
}

class _SheetXml {
  _SheetXml(this.xml);
  final String xml;
}

/// Collects cells by row and writes the worksheet.
class _Grid {
  final Map<int, Map<int, _Cell>> _rows = <int, Map<int, _Cell>>{};
  final Map<int, double> _heights = <int, double>{};
  final List<String> merges = <String>[];

  /// [row] and [col] are 1-based and 0-based respectively, like "A1".
  void set(int row, int col, _Cell cell) =>
      (_rows[row] ??= <int, _Cell>{})[col] = cell;

  void height(int row, double points) => _heights[row] = points;

  String sheetData() {
    final StringBuffer out = StringBuffer('<sheetData>');
    final List<int> rows = <int>{..._rows.keys, ..._heights.keys}.toList()
      ..sort();
    for (final int r in rows) {
      final double? h = _heights[r];
      out.write('<row r="$r"${h == null ? '' : ' ht="$h" customHeight="1"'}>');
      final Map<int, _Cell> cells = _rows[r] ?? <int, _Cell>{};
      for (final int c in cells.keys.toList()..sort()) {
        out.write(cells[c]!.xml('${_col(c)}$r'));
      }
      out.write('</row>');
    }
    out.write('</sheetData>');
    return out.toString();
  }
}

String _worksheet({
  required _Grid grid,
  required List<double> widths,
  int? freezeRows,
  String? autoFilter,
  bool landscape = false,
  bool drawing = false,
  bool onePage = false,
  required String footer,
}) {
  final StringBuffer out = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write(
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">',
    )
    ..write('<sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>')
    ..write('<sheetViews><sheetView showGridLines="0" workbookViewId="0"');
  if (freezeRows == null) {
    out.write('/>');
  } else {
    out.write(
      '><pane ySplit="$freezeRows" topLeftCell="A${freezeRows + 1}" '
      'activePane="bottomLeft" state="frozen"/>'
      '<selection pane="bottomLeft" activeCell="A${freezeRows + 1}" '
      'sqref="A${freezeRows + 1}"/></sheetView>',
    );
  }
  out
    ..write('</sheetViews>')
    ..write('<sheetFormatPr defaultRowHeight="15"/>')
    ..write('<cols>');
  for (int i = 0; i < widths.length; i++) {
    out.write(
      '<col min="${i + 1}" max="${i + 1}" width="${widths[i]}" customWidth="1"/>',
    );
  }
  out
    ..write('</cols>')
    ..write(grid.sheetData());
  if (autoFilter != null) out.write('<autoFilter ref="$autoFilter"/>');
  if (grid.merges.isNotEmpty) {
    out.write('<mergeCells count="${grid.merges.length}">');
    for (final String m in grid.merges) {
      out.write('<mergeCell ref="$m"/>');
    }
    out.write('</mergeCells>');
  }
  out
    ..write(
      '<pageMargins left="0.5" right="0.5" top="0.6" bottom="0.6" '
      'header="0.3" footer="0.3"/>',
    )
    ..write(
      '<pageSetup paperSize="9" orientation="${landscape ? 'landscape' : 'portrait'}" '
      'fitToWidth="1" fitToHeight="${onePage ? 1 : 0}"/>',
    )
    ..write(
      '<headerFooter><oddFooter>${_esc('&L&8$footer&R&8Page &P of &N')}'
      '</oddFooter></headerFooter>',
    );
  if (drawing) out.write('<drawing r:id="rId1"/>');
  out.write('</worksheet>');
  return out.toString();
}

/// A section heading with its yellow underline across [width] columns.
void _section(_Grid g, int row, String title, int width) {
  g.set(row, 0, _Cell.text(title.toUpperCase(), _S.section));
  for (int c = 1; c < width; c++) {
    g.set(row, c, const _Cell.blank(_S.section));
  }
  g.height(row, 20);
}

// ---------------------------------------------------------------------------
// Breakdown sheet

/// The Breakdown sheet's columns, which the chart and the Summary also
/// refer to.
class _Breakdown {
  _Breakdown(this.report, this.previous, this.audience)
    : owner = audience == SalesReportAudience.owner,
      daily = report.breakdown == SalesBreakdown.daily {
    keys = <String>[
      'date',
      if (daily) 'day',
      'count',
      if (owner) ...<String>[
        'gross',
        'share',
        'commission',
        'processing',
        'payout',
        'cash',
      ] else ...<String>['commission', 'share', 'perTxn'],
      if (previous != null) ...<String>['prior', 'change'],
    ];
  }

  final SalesReport report;
  final SalesReport? previous;
  final SalesReportAudience audience;
  final bool owner;
  final bool daily;
  late final List<String> keys;

  static const int headerRow = 4;
  int get firstRow => headerRow + 1;
  int get lastRow => headerRow + report.rows.length;
  int get totalRow => lastRow + 1;
  int get averageRow => lastRow + 2;

  String get headlineKey => owner ? 'gross' : 'commission';

  String letter(String key) => _col(keys.indexOf(key));

  /// e.g. "Breakdown!$D$5:$D$34".
  String range(String key) =>
      "Breakdown!\$${letter(key)}\$$firstRow:\$${letter(key)}\$$lastRow";

  String get lastLetter => _col(keys.length - 1);

  String header(String key) => switch (key) {
    'date' => daily ? 'Date' : 'Month',
    'day' => 'Day',
    'count' => 'Transactions',
    'gross' => 'Gross sales',
    'share' => 'Share',
    'commission' => 'Commission',
    'processing' => 'Processing (est.)',
    'payout' => 'Payout (est.)',
    'cash' => 'Overtime cash',
    'perTxn' => 'Per transaction',
    'prior' => 'Prior ${owner ? 'gross' : 'commission'}',
    'change' => 'Change',
    _ => key,
  };

  double columnWidth(String key) => switch (key) {
    'date' => daily ? 15 : 16,
    'day' => 7,
    'share' => 9,
    'change' => 10,
    'processing' || 'cash' => 17,
    _ => 15,
  };

  int headlineOf(SalesRow r) => salesHeadline(r, audience);

  SalesRow? priorRow(int i) =>
      previous != null && i < previous!.rows.length ? previous!.rows[i] : null;

  _SheetXml build(String scopeLabel) {
    final _Grid g = _Grid();
    final int width = keys.length;
    g.set(
      1,
      0,
      _Cell.text(
        '${daily ? 'Daily' : 'Monthly'} breakdown - '
        '${salesReportPeriod(report)}',
        _S.title,
      ),
    );
    g.height(1, 28);
    g.set(
      2,
      0,
      _Cell.text(
        '$scopeLabel  |  ${report.coveredLabel}  |  Amounts in Philippine '
        'pesos (PHP)',
        _S.muted,
      ),
    );
    for (int c = 0; c < width; c++) {
      final String key = keys[c];
      g.set(
        headerRow,
        c,
        _Cell.text(
          header(key),
          key == 'date' || key == 'day' ? _S.header : _S.headerRight,
        ),
      );
    }
    g.height(headerRow, 22);

    final int total = headlineOf(report.totals);
    final String head = letter(headlineKey);
    for (int i = 0; i < report.rows.length; i++) {
      final SalesRow row = report.rows[i];
      final int r = firstRow + i;
      final SalesRow? prior = priorRow(i);
      for (int c = 0; c < width; c++) {
        g.set(r, c, _rowCell(keys[c], row, r, head, total, prior));
      }
      g.height(r, 17);
    }

    // Totals.
    final int t = totalRow;
    for (int c = 0; c < width; c++) {
      final String key = keys[c];
      final String l = _col(c);
      final String sum = 'SUM($l$firstRow:$l$lastRow)';
      g.set(t, c, switch (key) {
        'date' => const _Cell.text('Total', _S.totalText),
        'day' => const _Cell.blank(_S.totalText),
        'count' => _Cell.formula(sum, _S.totalInt, number: report.totals.count),
        'share' => _Cell.formula(
          'IF($head$t=0,"",1)',
          _S.totalShare,
          number: total == 0 ? null : 1,
          text: total == 0 ? '' : null,
        ),
        'perTxn' => _perTxn(
          '${letter('commission')}$t',
          '${letter('count')}$t',
          report.totals.commissionCentavos,
          report.totals.count,
          _S.totalMoney,
        ),
        'change' => _changeCell(
          '$head$t',
          '${letter('prior')}$t',
          total,
          previous == null ? 0 : _priorSum(),
          _S.totalChange,
        ),
        'prior' => _Cell.formula(
          sum,
          _S.totalMoney,
          number: _pesos(_priorSum()),
        ),
        _ => _Cell.formula(
          sum,
          _S.totalMoney,
          number: _pesos(_amount(key, report.totals)),
        ),
      });
    }
    g.height(t, 18);

    // Averages.
    final int a = averageRow;
    final int n = report.rows.length;
    for (int c = 0; c < width; c++) {
      final String key = keys[c];
      final String l = _col(c);
      final String avg = 'AVERAGE($l$firstRow:$l$lastRow)';
      g.set(a, c, switch (key) {
        'date' => _Cell.text(
          'Average per ${salesRowNoun(report, plural: false)}',
          _S.avgText,
        ),
        'day' ||
        'share' ||
        'perTxn' ||
        'change' => const _Cell.blank(_S.avgText),
        'count' => _Cell.formula(
          avg,
          _S.avgDecimal,
          number: n == 0 ? 0 : report.totals.count / n,
        ),
        'prior' => _Cell.formula(
          avg,
          _S.avgMoney,
          number: n == 0 ? 0 : _pesos(_priorSum()) / n,
        ),
        _ => _Cell.formula(
          avg,
          _S.avgMoney,
          number: n == 0 ? 0 : _pesos(_amount(key, report.totals)) / n,
        ),
      });
    }

    final int notes = averageRow + 2;
    g.set(notes, 0, const _Cell.text('Notes', _S.metaLabel));
    final List<String> lines = <String>[
      if (previous != null)
        'Prior ${owner ? 'gross' : 'commission'} lines up the prior period '
            '${daily ? 'day by day' : 'month by month'} '
            '(${previous!.coveredLabel}).',
      if (owner)
        "Processing and payout are estimates; PayMongo's settlement report "
            'has the exact amounts.',
      'For internal record-keeping only. Not an official receipt or '
          'BIR-registered sales book.',
    ];
    for (int i = 0; i < lines.length; i++) {
      g.set(notes + 1 + i, 0, _Cell.text(lines[i], _S.muted));
    }

    return _SheetXml(
      _worksheet(
        grid: g,
        widths: <double>[for (final String k in keys) columnWidth(k)],
        freezeRows: headerRow,
        autoFilter: 'A$headerRow:$lastLetter$lastRow',
        landscape: keys.length > 8,
        footer: 'SmartPark  -  ${salesReportTitle(report, audience)}',
      ),
    );
  }

  int _priorSum() {
    int sum = 0;
    for (int i = 0; i < report.rows.length; i++) {
      final SalesRow? p = priorRow(i);
      if (p != null) sum += headlineOf(p);
    }
    return sum;
  }

  int _amount(String key, SalesRow r) => switch (key) {
    'gross' => r.grossCentavos,
    'commission' => r.commissionCentavos,
    'processing' => r.processingCentavos,
    'payout' => r.payoutCentavos,
    'cash' => r.cashCentavos,
    _ => 0,
  };

  _Cell _rowCell(
    String key,
    SalesRow row,
    int r,
    String head,
    int total,
    SalesRow? prior,
  ) {
    final bool empty = row.isEmpty;
    return switch (key) {
      'date' => _Cell.number(_serial(row.start), daily ? _S.date : _S.month),
      'day' => _Cell.text(
        salesWeekday(row.start),
        empty ? _S.textMutedRow : _S.text,
      ),
      'count' => _Cell.number(row.count, _S.integer),
      'share' => _Cell.formula(
        'IF($head\$$totalRow=0,"",$head$r/$head\$$totalRow)',
        _S.share,
        number: total == 0 ? null : headlineOf(row) / total,
        text: total == 0 ? '' : null,
      ),
      'perTxn' => _perTxn(
        '${letter('commission')}$r',
        '${letter('count')}$r',
        row.commissionCentavos,
        row.count,
        _S.money,
      ),
      'prior' =>
        prior == null
            ? const _Cell.blank(_S.money)
            : _Cell.number(_pesos(headlineOf(prior)), _S.money),
      'change' => _changeCell(
        '$head$r',
        '${letter('prior')}$r',
        headlineOf(row),
        prior == null ? 0 : headlineOf(prior),
        _S.change,
      ),
      _ => _Cell.number(_pesos(_amount(key, row)), _S.money),
    };
  }

  _Cell _perTxn(String amountRef, String countRef, int c, int n, int style) =>
      _Cell.formula(
        'IF($countRef=0,"",$amountRef/$countRef)',
        style,
        number: n == 0 ? null : _pesos(c) / n,
        text: n == 0 ? '' : null,
      );

  _Cell _changeCell(String nowRef, String priorRef, int now, int prior, int s) {
    final double? r = salesChange(now, prior);
    return _Cell.formula(
      'IF(N($priorRef)=0,"",$nowRef/$priorRef-1)',
      s,
      number: r,
      text: r == null ? '' : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Summary sheet

class _Summary {
  _Summary({
    required this.report,
    required this.previous,
    required this.audience,
    required this.scopeLabel,
    required this.preparedBy,
    required this.generated,
  });

  final SalesReport report;
  final SalesReport? previous;
  final SalesReportAudience audience;
  final String scopeLabel;
  final String preparedBy;
  final DateTime generated;

  /// Zero-based row the chart's top edge sits on.
  int chartRow = 0;

  static const int width = 5;

  _SheetXml build() {
    final bool owner = audience == SalesReportAudience.owner;
    final bool daily = report.breakdown == SalesBreakdown.daily;
    final List<SalesMetric> metrics = salesMetrics(report, previous, audience);
    final _Grid g = _Grid();

    g.set(1, 0, const _Cell.text('SMARTPARK', _S.brand));
    g.set(2, 0, _Cell.text(salesReportTitle(report, audience), _S.title));
    g.height(2, 30);
    g.set(3, 0, _Cell.text(scopeLabel, _S.muted));

    int r = 5;
    void meta(String label, String value) {
      g.set(r, 0, _Cell.text(label.toUpperCase(), _S.metaLabel));
      g.set(r, 1, _Cell.text(value, _S.metaValue));
      r++;
    }

    meta('Period', salesReportPeriod(report));
    if (report.isPartial) meta('Covers', report.coveredLabel);
    if (previous != null) meta('Compared to', previous!.coveredLabel);
    meta('Generated', _stamp(generated));
    if (preparedBy.isNotEmpty) meta('Prepared by', preparedBy);

    // Key figures as tiles: label, value, change.
    r++;
    _section(g, r, 'Key figures', width);
    r += 1;
    final List<(String, SalesMetric)> tiles = <(String, SalesMetric)>[
      (metrics[0].label, metrics[0]),
      ('Transactions', metrics[1]),
      ('Avg. per transaction', metrics[2]),
      owner ? ('Take-home (est.)', metrics[7]) : (metrics[3].label, metrics[3]),
    ];
    for (int i = 0; i < tiles.length; i++) {
      final (String label, SalesMetric m) = tiles[i];
      g.set(r, i, _Cell.text(label.toUpperCase(), _S.kpiLabel));
      g.set(
        r + 1,
        i,
        m.unit == SalesUnit.money
            ? _Cell.number(_pesos(m.current), _S.kpiMoney)
            : _Cell.number(m.current, _S.kpiInt),
      );
      final double? ratio = m.ratio;
      g.set(
        r + 2,
        i,
        ratio == null
            ? _Cell.text(
                previous == null ? 'No comparison' : 'No prior figure',
                _S.kpiText,
              )
            : _Cell.number(ratio, _S.kpiChange),
      );
    }
    g.height(r, 20);
    g.height(r + 1, 24);
    g.height(r + 2, 18);
    r += 4;

    // Comparison.
    if (previous != null) {
      _section(g, r, 'Period comparison', width);
      r++;
      const List<String> heads = <String>[
        'Metric',
        'This period',
        'Prior period',
        'Change',
        '% Change',
      ];
      for (int c = 0; c < heads.length; c++) {
        g.set(r, c, _Cell.text(heads[c], c == 0 ? _S.header : _S.headerRight));
      }
      g.height(r, 22);
      r++;
      for (int i = 0; i < metrics.length; i++) {
        final SalesMetric m = metrics[i];
        final bool money = m.unit == SalesUnit.money;
        num v(int x) => money ? _pesos(x) : x;
        g.set(r, 0, _Cell.text(m.label, i == 0 ? _S.textBold : _S.text));
        g.set(r, 1, _Cell.number(v(m.current), money ? _S.money : _S.integer));
        g.set(
          r,
          2,
          _Cell.number(v(m.previous ?? 0), money ? _S.money : _S.integer),
        );
        g.set(
          r,
          3,
          _Cell.formula(
            'B$r-C$r',
            money ? _S.moneyChange : _S.intChange,
            number: v(m.change ?? 0),
          ),
        );
        g.set(
          r,
          4,
          _Cell.formula(
            'IF(C$r=0,"n/a",(B$r-C$r)/C$r)',
            _S.change,
            number: m.ratio,
            text: m.ratio == null ? 'n/a' : null,
          ),
        );
        g.height(r, 17);
        r++;
      }
      r++;
    }

    // Insights.
    _section(g, r, 'Insights', width);
    r++;
    g.set(
      r,
      0,
      _Cell.text(salesNarrative(report, previous, audience), _S.narrative),
    );
    for (int c = 1; c < width; c++) {
      g.set(r, c, const _Cell.blank(_S.narrative));
    }
    g.merges.add('A$r:${_col(width - 1)}$r');
    g.height(r, 54);
    r += 2;

    final SalesRow? best = report.bestBy(
      (SalesRow row) => salesHeadline(row, audience),
    );
    final int n = report.rows.length;
    void insight(String label, String detail, _Cell value) {
      g.set(r, 0, _Cell.text(label, _S.text));
      g.set(r, 1, _Cell.text(detail, _S.text));
      g.set(r, 2, value);
      g.height(r, 17);
      r++;
    }

    final String noun = salesRowNoun(report, plural: false);
    insight(
      'Best $noun',
      best == null
          ? '-'
          : daily
          ? '${salesWeekday(best.start)}, ${report.rowLabel(best)}'
          : report.rowLabel(best),
      _Cell.number(
        _pesos(best == null ? 0 : salesHeadline(best, audience)),
        _S.money,
      ),
    );
    insight(
      'Average per $noun',
      '',
      _Cell.number(
        n == 0 ? 0 : _pesos(salesHeadline(report.totals, audience)) / n,
        _S.money,
      ),
    );
    insight(
      '${daily ? 'Days' : 'Months'} with sales',
      '${salesActiveRows(report)} of $n',
      _Cell.number(n == 0 ? 0 : salesActiveRows(report) / n, _S.share),
    );
    if (daily && n > 7) {
      final ({List<int> totals, List<int> days}) w = salesByWeekday(
        report,
        audience,
      );
      int top = -1;
      double topAvg = 0;
      for (int i = 0; i < 7; i++) {
        final double avg = w.days[i] == 0 ? 0 : w.totals[i] / w.days[i];
        if (avg > topAvg) {
          topAvg = avg;
          top = i;
        }
      }
      insight(
        'Busiest day of week (avg.)',
        top < 0 ? '-' : kSalesWeekdays[top],
        _Cell.number(_pesos(topAvg.round()), _S.money),
      );
    }
    if (owner) {
      final int gross = report.totals.grossCentavos;
      insight(
        'Fees as share of gross',
        'Commission + processing',
        _Cell.number(
          gross == 0
              ? 0
              : (report.totals.commissionCentavos +
                        report.totals.processingCentavos) /
                    gross,
          _S.share,
        ),
      );
    }
    r++;

    // Chart.
    _section(
      g,
      r,
      '${salesHeadlineName(audience)} per $noun'
      '${previous == null ? '' : ' vs prior period'}',
      width,
    );
    r++;
    chartRow = r - 1; // zero-based row index of the chart's top edge
    r += 21;

    g.set(r, 0, const _Cell.text('Notes', _S.metaLabel));
    r++;
    final List<String> notes = <String>[
      if (owner) ...<String>[
        'Gross sales are in-app payments for paid tickets. Commission is '
            "SmartPark's platform fee.",
        "Processing is an estimate of PayMongo's fee, so the payout is an "
            "estimate too; PayMongo's settlement report has the exact amounts.",
        'Overtime cash is collected at the gate and counted on the day it '
            'was collected.',
      ] else
        "Commission is SmartPark's platform fee on in-app parking payments, "
            'across all facilities.',
      'The prior period is the one before this, cut at the same point while '
          'this one is still running.',
      'For internal record-keeping only. Not an official receipt or '
          'BIR-registered sales book.',
    ];
    for (final String line in notes) {
      g.set(r, 0, _Cell.text(line, _S.muted));
      r++;
    }

    return _SheetXml(
      _worksheet(
        grid: g,
        widths: const <double>[30, 22, 22, 18, 14],
        onePage: true,
        drawing: true,
        footer: 'SmartPark  -  ${salesReportTitle(report, audience)}',
      ),
    );
  }
}

String _stamp(DateTime t) {
  final int hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final String minute = t.minute.toString().padLeft(2, '0');
  return '${kSalesMonthNames[t.month - 1].substring(0, 3)} ${t.day}, ${t.year} '
      '$hour:$minute ${t.hour < 12 ? 'AM' : 'PM'}';
}

// ---------------------------------------------------------------------------
// Chart

String _chartXml(
  SalesReport report,
  SalesReport? previous,
  SalesReportAudience audience,
  _Breakdown b,
) {
  final bool daily = report.breakdown == SalesBreakdown.daily;
  final int n = report.rows.length;
  final String dateFormat = daily ? 'mmm d' : 'mmm yyyy';

  String numCache(String format, List<num?> values) {
    final StringBuffer out = StringBuffer(
      '<c:numCache><c:formatCode>${_esc(format)}</c:formatCode>'
      '<c:ptCount val="${values.length}"/>',
    );
    for (int i = 0; i < values.length; i++) {
      if (values[i] == null) continue;
      out.write('<c:pt idx="$i"><c:v>${_Cell._num(values[i]!)}</c:v></c:pt>');
    }
    out.write('</c:numCache>');
    return out.toString();
  }

  final String cat =
      '<c:cat><c:numRef><c:f>${b.range('date')}</c:f>'
      '${numCache(dateFormat, <num>[for (final SalesRow r in report.rows) _serial(r.start)])}'
      '</c:numRef></c:cat>';

  String series(int idx, String name, String color, String key, List<num?> v) =>
      '<c:ser><c:idx val="$idx"/><c:order val="$idx"/>'
      '<c:tx><c:v>${_esc(name)}</c:v></c:tx>'
      '<c:spPr><a:solidFill><a:srgbClr val="$color"/></a:solidFill>'
      '<a:ln><a:noFill/></a:ln></c:spPr>'
      '<c:invertIfNegative val="0"/>'
      '$cat'
      '<c:val><c:numRef><c:f>${b.range(key)}</c:f>'
      '${numCache('#,##0.00', v)}</c:numRef></c:val>'
      '</c:ser>';

  final String headline = salesHeadlineName(audience);
  final StringBuffer sers = StringBuffer();
  if (previous != null) {
    sers.write(
      series(0, 'Prior period', 'C9CCD4', 'prior', <num?>[
        for (int i = 0; i < n; i++)
          i < previous.rows.length
              ? _pesos(salesHeadline(previous.rows[i], audience))
              : null,
      ]),
    );
  }
  sers.write(
    series(
      previous == null ? 0 : 1,
      'This period',
      '1F2128',
      b.headlineKey,
      <num>[
        for (final SalesRow r in report.rows)
          _pesos(salesHeadline(r, audience)),
      ],
    ),
  );

  const String axisText =
      '<c:txPr><a:bodyPr/><a:lstStyle/><a:p><a:pPr><a:defRPr sz="800">'
      '<a:solidFill><a:srgbClr val="6B7080"/></a:solidFill>'
      '<a:latin typeface="Arial"/></a:defRPr></a:pPr>'
      '<a:endParaRPr lang="en-US"/></a:p></c:txPr>';

  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
      '<c:roundedCorners val="0"/>'
      '<c:chart>'
      '<c:title><c:tx><c:rich><a:bodyPr/><a:lstStyle/><a:p><a:pPr>'
      '<a:defRPr sz="1100" b="1"/></a:pPr><a:r><a:rPr lang="en-US" sz="1100" b="1">'
      '<a:solidFill><a:srgbClr val="1F2128"/></a:solidFill>'
      '<a:latin typeface="Arial"/></a:rPr>'
      '<a:t>${_esc('$headline per ${daily ? 'day' : 'month'} (PHP)')}</a:t>'
      '</a:r></a:p></c:rich></c:tx><c:overlay val="0"/></c:title>'
      '<c:autoTitleDeleted val="0"/>'
      '<c:plotArea><c:layout/>'
      '<c:barChart><c:barDir val="col"/><c:grouping val="clustered"/>'
      '<c:varyColors val="0"/>'
      '$sers'
      '<c:gapWidth val="${previous == null ? 60 : 50}"/>'
      '<c:overlap val="${previous == null ? 0 : -5}"/>'
      '<c:axId val="50010"/><c:axId val="50020"/>'
      '</c:barChart>'
      '<c:catAx><c:axId val="50010"/><c:scaling><c:orientation val="minMax"/>'
      '</c:scaling><c:delete val="0"/><c:axPos val="b"/>'
      '<c:numFmt formatCode="${_esc(daily ? 'mmm d' : 'mmm')}" sourceLinked="0"/>'
      '<c:majorTickMark val="none"/><c:minorTickMark val="none"/>'
      '<c:tickLblPos val="nextTo"/>'
      '<c:spPr><a:ln w="9525"><a:solidFill><a:srgbClr val="6B7080"/></a:solidFill>'
      '</a:ln></c:spPr>'
      '$axisText'
      '<c:crossAx val="50020"/><c:crosses val="autoZero"/><c:auto val="0"/>'
      '<c:lblAlgn val="ctr"/><c:lblOffset val="100"/><c:noMultiLvlLbl val="0"/>'
      '</c:catAx>'
      '<c:valAx><c:axId val="50020"/><c:scaling><c:orientation val="minMax"/>'
      '</c:scaling><c:delete val="0"/><c:axPos val="l"/>'
      '<c:majorGridlines><c:spPr><a:ln w="6350"><a:solidFill>'
      '<a:srgbClr val="DCDFE5"/></a:solidFill></a:ln></c:spPr></c:majorGridlines>'
      '<c:numFmt formatCode="#,##0" sourceLinked="0"/>'
      '<c:majorTickMark val="none"/><c:minorTickMark val="none"/>'
      '<c:tickLblPos val="nextTo"/>'
      '<c:spPr><a:ln><a:noFill/></a:ln></c:spPr>'
      '$axisText'
      '<c:crossAx val="50010"/><c:crosses val="autoZero"/>'
      '<c:crossBetween val="between"/>'
      '</c:valAx>'
      '<c:spPr><a:noFill/><a:ln><a:noFill/></a:ln></c:spPr>'
      '</c:plotArea>'
      '<c:legend><c:legendPos val="t"/><c:overlay val="0"/>$axisText</c:legend>'
      '<c:plotVisOnly val="1"/><c:dispBlanksAs val="gap"/>'
      '</c:chart>'
      '<c:spPr><a:solidFill><a:srgbClr val="FFFFFF"/></a:solidFill>'
      '<a:ln><a:noFill/></a:ln></c:spPr>'
      '</c:chartSpace>';
}

String _drawingXml(int fromRow, int toRow) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
    '<xdr:twoCellAnchor editAs="oneCell">'
    '<xdr:from><xdr:col>0</xdr:col><xdr:colOff>0</xdr:colOff>'
    '<xdr:row>$fromRow</xdr:row><xdr:rowOff>76200</xdr:rowOff></xdr:from>'
    '<xdr:to><xdr:col>${_Summary.width}</xdr:col><xdr:colOff>0</xdr:colOff>'
    '<xdr:row>$toRow</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to>'
    '<xdr:graphicFrame macro="">'
    '<xdr:nvGraphicFramePr><xdr:cNvPr id="2" name="Trend chart"/>'
    '<xdr:cNvGraphicFramePr/></xdr:nvGraphicFramePr>'
    '<xdr:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/></xdr:xfrm>'
    '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart">'
    '<c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" '
    'r:id="rId1"/></a:graphicData></a:graphic>'
    '</xdr:graphicFrame><xdr:clientData/></xdr:twoCellAnchor></xdr:wsDr>';

// ---------------------------------------------------------------------------
// Package parts

const String _contentTypes =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    '<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    '<Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>'
    '<Override PartName="/xl/charts/chart1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/>'
    '<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>'
    '<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>'
    '</Types>';

const String _rootRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>'
    '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>'
    '</Relationships>';

const String _appXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties">'
    '<Application>SmartPark</Application></Properties>';

String _coreXml(String title, String author, DateTime now) {
  final String iso = '${now.toUtc().toIso8601String().split('.').first}Z';
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
      'xmlns:dc="http://purl.org/dc/elements/1.1/" '
      'xmlns:dcterms="http://purl.org/dc/terms/" '
      'xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
      '<dc:title>${_esc(title)}</dc:title>'
      '<dc:creator>${_esc(author.isEmpty ? 'SmartPark' : author)}</dc:creator>'
      '<dcterms:created xsi:type="dcterms:W3CDTF">$iso</dcterms:created>'
      '</cp:coreProperties>';
}

String _workbookXml(_Breakdown b) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
    '<bookViews><workbookView activeTab="0"/></bookViews>'
    '<sheets>'
    '<sheet name="Summary" sheetId="1" r:id="rId1"/>'
    '<sheet name="Breakdown" sheetId="2" r:id="rId2"/>'
    '</sheets>'
    '<definedNames>'
    '<definedName name="_xlnm._FilterDatabase" localSheetId="1" hidden="1">'
    "Breakdown!\$A\$${_Breakdown.headerRow}:\$${b.lastLetter}\$${b.lastRow}"
    '</definedName>'
    '<definedName name="_xlnm.Print_Titles" localSheetId="1">'
    "Breakdown!\$${_Breakdown.headerRow}:\$${_Breakdown.headerRow}"
    '</definedName>'
    '</definedNames>'
    '<calcPr calcId="191029" fullCalcOnLoad="1"/>'
    '</workbook>';

const String _workbookRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>'
    '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '</Relationships>';

const String _sheetDrawingRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/>'
    '</Relationships>';

const String _drawingRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart1.xml"/>'
    '</Relationships>';
