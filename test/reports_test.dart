import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_app/export.dart';
import 'package:warehouse_app/models.dart';
import 'package:warehouse_app/store.dart';
import 'package:warehouse_app/xlsx.dart';

WarehouseStore seeded() => WarehouseStore(null)
  ..applyJson(jsonDecode(File('seed/app_seed.json').readAsStringSync()) as Map<String, dynamic>, save: false);

void main() {
  test('monthly use combines Excel history with app receipts', () {
    final s = seeded();
    final m = s.monthlyIssued();
    expect(m['P001']!['2025-09'], 210); // Year sheet, first month
    // September 2026 comes from receipts, not the Year sheet.
    final sept = s.receipts.where((r) => r.date?.startsWith('2026-09') ?? false).expand((r) => r.lines)
        .where((l) => l.itemId == 'P001').fold<num>(0, (t, l) => t + l.qty);
    expect(m['P001']!['2026-09'], sept);
  });

  test('issued by department adds up to all receipts in range', () {
    final s = seeded();
    final d = s.issuedByDepartment('2026-09-01', '2026-09-30');
    final total = d.values.expand((x) => x.values).fold<num>(0, (a, b) => a + b);
    final expected = s.receipts.where((r) => r.date != null && r.date!.startsWith('2026-09'))
        .expand((r) => r.lines).fold<num>(0, (a, l) => a + l.qty);
    expect(total, expected);
    expect(d.keys, containsAll(['NICU', 'Hotel', 'Operation']));
  });

  test('payments and equipment match the Excel sheets', () {
    final s = seeded();
    expect(s.payments.fold<num>(0, (t, p) => t + p.remaining), 259759); // تسديد total remaining
    final tool = s.equipment.firstWhere((e) => e.name == 'يدة لكشور تب قصير');
    expect(tool.usedQty, 3);
    expect(tool.nowQty, 4);
    tool.usageDates.add('2026-10-01');
    s.saveEquipment(tool, index: s.equipment.indexOf(tool));
    expect(s.equipment.firstWhere((e) => e.name == 'يدة لكشور تب قصير').nowQty, 3);
    s.savePayment(Payment(no: s.nextPaymentNo, supplier: 'زانيار', amount: 100, paid: 100));
    expect(s.payments.last.settled, isTrue);
  });

  test('Excel export is a valid workbook with every sheet', () {
    final s = seeded();
    final bytes = buildXlsx(workbookSheets(s, DateTime(2026, 10, 1)));
    final zip = ZipDecoder().decodeBytes(bytes);
    expect(zip.files.where((f) => f.name.startsWith('xl/worksheets/')).length, 8);
    File('build/export-test.xlsx')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  });
}
