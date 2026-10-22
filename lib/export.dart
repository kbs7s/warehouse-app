import 'expiry.dart';
import 'l10n.dart';
import 'models.dart';
import 'platform/files.dart';
import 'store.dart';
import 'ui.dart';
import 'xlsx.dart';

/// The last [n] months ending with [end] (yyyy-MM), oldest first.
List<String> lastMonths(DateTime end, [int n = 12]) => [
      for (var i = n - 1; i >= 0; i--) isoDate(DateTime(end.year, end.month - i)).substring(0, 7),
    ];

String monthLabel(String ym) => fmtMonth(ym);

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
  final sheets = [
    Sheet(tx('Stock', 'المخزون'), [
      for (final (en, ar) in [('Code', 'الرمز'), ('Item', 'المادة'), ('Unit', 'الوحدة'), ('Opening', 'الافتتاحي'), ('Bought', 'المشترى'),
        ('Issued', 'المصروف'), ('In stock', 'الموجود'), ('Minimum', 'الحد الأدنى'), ('Status', 'الحالة')]) tx(en, ar),
    ], [
      for (final st in s.stockList)
        [
          st.item.id, st.item.name, st.item.unit, st.item.openingQty, st.bought, st.issued, st.qty, st.item.minLevel,
          switch (st.status) {
            StockStatus.inStock => tx('In stock', 'متوفر'),
            StockStatus.low => tx('Low', 'قليل'),
            StockStatus.out => tx('Out', 'نافد'),
          },
        ],
    ]),
    Sheet(tx('Issue receipts', 'وصولات الصرف'), [
      for (final (en, ar) in [('Receipt #', 'رقم الوصل'), ('Date', 'التاريخ'), ('Department', 'القسم'), ('Received by', 'المستلم'),
        ('Code', 'الرمز'), ('Item', 'المادة'), ('Qty', 'الكمية'), ('Unit', 'الوحدة'), ('Note', 'ملاحظة')]) tx(en, ar),
    ], [
      for (final r in s.receipts)
        for (final l in r.lines)
          [r.no, r.date, r.department, r.customer, l.itemId, name(l.itemId), l.qty, unit(l.itemId), r.note],
    ]),
    Sheet(tx('Purchases', 'المشتريات'), [
      for (final (en, ar) in [('Purchase #', 'رقم الشراء'), ('Date', 'التاريخ'), ('Supplier', 'المجهز'), ('Code', 'الرمز'), ('Item', 'المادة'),
        ('Qty', 'الكمية'), ('Unit', 'الوحدة'), ('Unit price', 'سعر الوحدة'), ('Total', 'المجموع'), ('Expiry', 'تاريخ الانتهاء'),
        ('Lot', 'الوجبة'), ('Note', 'ملاحظة')]) tx(en, ar),
    ], [
      for (final p in s.purchases)
        for (final l in p.lines)
          [p.no, p.date, p.supplier, l.itemId, name(l.itemId), l.qty, unit(l.itemId), l.unitPrice, l.total, l.expiry, l.lot, l.note ?? p.note],
    ]),
    Sheet(tx('Supplier payments', 'تسديد المشتريات'), [
      for (final (en, ar) in [('Purchase #', 'رقم الشراء'), ('Date', 'التاريخ'), ('Supplier', 'المجهز'), ("Supplier's bill no.", 'رقم قائمة المجهز'),
        ('Total', 'المجموع'), ('Paid', 'المدفوع'), ('Still owed', 'المتبقي')]) tx(en, ar),
    ], [
      for (final p in s.purchases)
        if (p.tracked) [p.no, p.date, p.supplier, p.ref, p.total, p.paid, p.owed],
    ]),
    Sheet(tx('Monthly use', 'الاستهلاك الشهري'),
        [tx('Code', 'الرمز'), tx('Item', 'المادة'), tx('Unit', 'الوحدة'), ...months.map(monthLabel), tx('Total', 'المجموع')], [
      for (final i in s.activeItems)
        [
          i.id, i.name, i.unit,
          for (final m in months) monthly[i.id]?[m] ?? 0,
          months.fold<num>(0, (t, m) => t + (monthly[i.id]?[m] ?? 0)),
        ],
    ]),
    Sheet(tx('Supplier payments', 'فواتير المجهزين'), [
      for (final (en, ar) in [('#', '#'), ('Supplier', 'المجهز'), ('Date', 'التاريخ'), ('Amount', 'المبلغ'), ('Paid', 'المدفوع'),
        ('Remaining', 'المتبقي'), ('Status', 'الحالة'), ('Details', 'التفاصيل')]) tx(en, ar),
    ], [
      for (final p in s.payments)
        [p.no, p.supplier, p.date, p.amount, p.paid, p.remaining, p.settled ? tx('Paid', 'مسددة') : tx('Owed', 'غير مسددة'), p.details],
    ]),
    Sheet(tx('Surgery equipment', 'معدات العمليات'), [
      for (final (en, ar) in [('Tool', 'الأداة'), ('Received', 'الاستلام'), ('Start', 'البداية'), ('Bought', 'المشترى'), ('Issued', 'المصروف'),
        ('Now', 'الآن'), ('Movements', 'الحركات')]) tx(en, ar),
    ], [
      for (final e in s.equipment)
        [
          e.name, e.dateReceived, e.startQty, e.bought, e.issued, e.nowQty,
          [
            ...e.usageDates,
            for (final m in e.moves) '${m.isBuy ? '+' : '-'}${fmtQty(m.qty)} ${m.date}${m.party == null ? '' : ' ${m.party}'}',
          ].join(', '),
        ],
    ]),
    Sheet(tx('Expiry dates', 'تواريخ الانتهاء'), [
      for (final (en, ar) in [('Code', 'الرمز'), ('Item', 'المادة'), ('Unit', 'الوحدة'), ('Expiry date', 'تاريخ الانتهاء'), ('Quantity', 'الكمية'),
        ('Lot', 'التشغيلة'), ('Days left', 'الأيام المتبقية'), ('In stock now', 'الموجود الآن')]) tx(en, ar),
    ], [
      for (final e in s.expiryList(all: true))
        [e.item.id, e.item.name, e.item.unit, e.batch.date, e.batch.qty, e.batch.lot, e.daysLeft, s.stock(e.item.id).qty],
    ]),
  ];
  // Arabic workbooks open right to left, like the old Excel file.
  return [for (final x in sheets) Sheet(x.name, x.header, x.rows, rightToLeft: isAr)];
}

Future<void> exportExcel(WarehouseStore s) async {
  final now = DateTime.now();
  await downloadFile('warehouse-${isoDate(now)}.xlsx', buildXlsx(workbookSheets(s, now)),
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
}
