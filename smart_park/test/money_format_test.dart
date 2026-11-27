import 'package:flutter_test/flutter_test.dart';
import 'package:smart_park/widgets/smartpark_ui.dart';
import 'package:smart_park/widgets/sp_audit_format.dart';

void main() {
  test('short chart labels drop a trailing .0', () {
    expect(spCompactPeso(1000), 'PHP 1k');
    expect(spCompactPeso(1250), 'PHP 1.3k');
    expect(spCompactPeso(2000000), 'PHP 2M');
    expect(spCompactPeso(450), 'PHP 450');
  });

  test('Change History amounts have a thousands comma', () {
    expect(spAuditValueText(103000, field: 'amountCentavos'), 'PHP 1,030');
    expect(spAuditValueText(1030, field: 'overtimeAmount'), 'PHP 1,030.00');
  });
}
