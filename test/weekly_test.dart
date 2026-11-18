import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_app/screens/departments_screen.dart';
import 'package:warehouse_app/screens/weekly_screen.dart';
import 'package:warehouse_app/store.dart';

void main() {
  test('weeks run Saturday to Friday', () {
    // 18 Nov 2026 is a Wednesday: its week starts Saturday 14 Nov.
    expect(weekStart(DateTime(2026, 11, 18)), DateTime(2026, 11, 14));
    expect(weekStart(DateTime(2026, 11, 14, 22)), DateTime(2026, 11, 14)); // Saturday itself
    expect(weekStart(DateTime(2026, 11, 20)), DateTime(2026, 11, 14)); // Friday
    expect(weekStart(DateTime(2026, 11, 21)), DateTime(2026, 11, 21)); // next Saturday
    expect(weekRange(DateTime(2026, 11, 14)), ('2026-11-14', '2026-11-20'));
    expect(weekRange(DateTime(2026, 12, 26)), ('2026-12-26', '2027-01-01'));
  });

  test('a week report adds up to the receipts of that week', () {
    final s = WarehouseStore(null)
      ..applyJson(jsonDecode(File('seed/app_seed.json').readAsStringSync()) as Map<String, dynamic>, save: false);
    final dated = [for (final r in s.allReceipts) if (r.date != null) r.date!]..sort();
    final start = weekStart(DateTime.parse(dated.last));
    final (from, to) = weekRange(start);
    final use = departmentUse(s, from, to);
    final expected = s.allReceipts
        .where((r) => r.date != null && r.date!.compareTo(from) >= 0 && r.date!.compareTo(to) <= 0)
        .expand((r) => r.lines)
        .fold<num>(0, (a, l) => a + l.qty);
    expect(expected, greaterThan(0));
    expect(use.fold<num>(0, (a, d) => a + d.total), expected);
  });
}
