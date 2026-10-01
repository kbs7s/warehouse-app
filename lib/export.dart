import 'models.dart';
import 'platform/files.dart';
import 'store.dart';
import 'ui.dart';
import 'xlsx.dart';

/// The last [n] months ending with [end] (yyyy-MM), oldest first.
List<String> lastMonths(DateTime end, [int n = 12]) => [
      for (var i = n - 1; i >= 0; i--) isoDate(DateTime(end.year, end.month - i)).substring(0, 7),
    ];

String monthLabel(String ym) {
  const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${names[int.parse(ym.substring(5)) - 1]} ${ym.substring(2, 4)}';
}

/// Average issued per month over the last 3 full months plus this one.
num avgMonthlyUse(Map<String, num>? byMonth, DateTime now) {
  if (byMonth == null) return 0;
  final months = lastMonths(now, 4).take(3);
  return months.fold<num>(0, (s, m) => s + (byMonth[m] ?? 0)) / 3;
}

/// Everything in one Excel workbook, one sheet per area.
List<Sheet> workbookSheets(WarehouseStore s, DateTime now) {
  String name(String id) => s.item(id)?.name ?? id;
  String unit(String id) => s.item(id)?.unit ?? '';
  final monthly = s.monthlyIssued();
  final months = lastMonths(now);
  return [
    Sheet('Stock', ['Code', 'Item', 'Unit', 'Opening', 'Bought', 'Issued', 'In stock', 'Minimum', 'Status'], [
      for (final st in s.stockList)
        [
          st.item.id, st.item.name, st.item.unit, st.item.openingQty, st.bought, st.issued, st.qty, st.item.minLevel,
          switch (st.status) { StockStatus.inStock => 'In stock', StockStatus.low => 'Low', StockStatus.out => 'Out' },
        ],
    ]),
    Sheet('Issue receipts', ['Receipt #', 'Date', 'Department', 'Received by', 'Code', 'Item', 'Qty', 'Unit', 'Note'], [
      for (final r in s.receipts)
        for (final l in r.lines)
          [r.no, r.date, r.department, r.customer, l.itemId, name(l.itemId), l.qty, unit(l.itemId), r.note],
    ]),
    Sheet('Purchases', ['Purchase #', 'Date', 'Supplier', 'Code', 'Item', 'Qty', 'Unit', 'Unit price', 'Total', 'Note'], [
      for (final p in s.purchases)
        for (final l in p.lines)
          [p.no, p.date, p.supplier, l.itemId, name(l.itemId), l.qty, unit(l.itemId), l.unitPrice, l.total, l.note ?? p.note],
    ]),
    Sheet('Monthly use', ['Code', 'Item', 'Unit', ...months.map(monthLabel), 'Total'], [
      for (final i in s.activeItems)
        [
          i.id, i.name, i.unit,
          for (final m in months) monthly[i.id]?[m] ?? 0,
          months.fold<num>(0, (t, m) => t + (monthly[i.id]?[m] ?? 0)),
        ],
    ]),
    Sheet('Supplier payments', ['#', 'Supplier', 'Date', 'Amount', 'Paid', 'Remaining', 'Status', 'Details'], [
      for (final p in s.payments)
        [p.no, p.supplier, p.date, p.amount, p.paid, p.remaining, p.settled ? 'Paid' : 'Owed', p.details],
    ]),
    Sheet('Surgery equipment', ['Tool', 'Received', 'Start', 'Bought', 'Used', 'Now', 'Used on'], [
      for (final e in s.equipment)
        [e.name, e.dateReceived, e.startQty, e.boughtQty, e.usedQty, e.nowQty, e.usageDates.join(', ')],
    ]),
  ];
}

Future<void> exportExcel(WarehouseStore s) async {
  final now = DateTime.now();
  await downloadFile('warehouse-${isoDate(now)}.xlsx', buildXlsx(workbookSheets(s, now)),
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
}
