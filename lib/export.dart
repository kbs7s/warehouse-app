import 'expiry.dart';
import 'l10n.dart';
import 'models.dart';
import 'month.dart';
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
  final monthly = s.monthlyIssued();
  final months = lastMonths(now);
  final spentMonth = s.spentThisMonth, spentYear = s.spentThisYear;
  final sheets = [
    Sheet(tx('Stock', 'المخزون'), [
      for (final (en, ar) in [('Code', 'الرمز'), ('Item', 'المادة'), ('Unit', 'الوحدة'), ('Kept in', 'مكان الخزن'), ('Start of month', 'رصيد أول الشهر'),
        ('Bought', 'المشترى'), ('Issued', 'المصروف'), ('Main store', 'المخزن الأساسي'), ('Reserve store', 'مخزن الاحتياط'), ('Both stores', 'المجموع'),
        ('Minimum', 'الحد الأدنى'), ('Status', 'الحالة'), ('Spent this month', 'مصروف الشهر'), ('Spent this year', 'مصروف السنة')]) tx(en, ar),
    ], [
      for (final st in s.allStockList)
        [
          st.item.id, st.item.name, st.item.unit,
          st.item.reserveOnly ? tx('Reserve only', 'الاحتياط فقط') : tx('Main store', 'الأساسي'),
          st.item.openingQty, st.bought, st.issued + st.sold, st.qty, st.reserve, st.total, st.item.minLevel,
          st.item.reserveOnly
              ? ''
              : switch (st.status) {
                  StockStatus.inStock => tx('In stock', 'متوفر'),
                  StockStatus.low => tx('Low', 'قليل'),
                  StockStatus.out => tx('Out', 'نافد'),
                },
          spentMonth[st.item.id] ?? 0, spentYear[st.item.id] ?? 0,
        ],
    ]),
    Sheet(tx('Reserve store', 'مخزن الاحتياط'), [
      for (final (en, ar) in [('Code', 'الرمز'), ('Item', 'المادة'), ('Unit', 'الوحدة'), ('Kept in', 'مكان الخزن'), ('In reserve', 'في الاحتياط'),
        ('In main store', 'في الأساسي')]) tx(en, ar),
    ], [
      for (final st in s.reserveStockList)
        [st.item.id, st.item.name, st.item.unit, st.item.reserveOnly ? tx('Reserve only', 'الاحتياط فقط') : tx('Both', 'كلاهما'), st.reserve,
          st.item.reserveOnly ? null : st.qty],
    ]),
    issuesSheet(s, [for (final m in s.monthCloses) for (final r in m.issueList) (m.from, r), for (final r in s.receipts) (s.openMonthStart, r)]),
    purchasesSheet(s, [for (final m in s.monthCloses) for (final p in m.purchaseList) (m.from, p), for (final p in s.purchases) (s.openMonthStart, p)]),
    Sheet(tx('Supplier payments', 'تسديد المشتريات'), [
      for (final (en, ar) in [('Purchase #', 'رقم الشراء'), ('Date', 'التاريخ'), ('Supplier', 'المجهز'), ("Supplier's bill no.", 'رقم قائمة المجهز'),
        ('Total', 'المجموع'), ('Paid', 'المدفوع'), ('Still owed', 'المتبقي')]) tx(en, ar),
    ], [
      for (final p in s.purchases)
        if (p.tracked) [p.no, p.date, p.supplier, p.ref, p.total, p.paid, p.owed],
      for (final b in s.payments)
        if (b.carriedFrom != null) [b.details, b.date, b.supplier, null, b.amount, b.paid, b.remaining],
    ]),
    movesSheet(s, [for (final m in s.monthCloses) for (final t in m.transferList) (m.from, t), for (final t in s.transfers) (s.openMonthStart, t)]),
    departmentsSheet(s, s.allReceipts),
    Sheet(tx('Months', 'الأشهر'), [
      tx('Month', 'الشهر'), tx('From', 'من'), tx('To', 'إلى'), tx('Issues', 'وصولات الصرف'), tx('Purchases', 'المشتريات'),
      tx('Spent (units)', 'المصروف (وحدة)'), tx('Received (units)', 'الوارد (وحدة)'),
      for (final k in monthStatKeys) tx(k.$2, k.$3),
    ], [
      for (final m in s.monthCloses.reversed)
        [fmtMonth(m.from), m.from, m.to, m.receipts, m.purchaseList.length, m.issued, m.received, for (final k in monthStatKeys) m.stats[k.$1]],
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
    Sheet(tx('Older bills', 'قوائم سابقة'), [
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
    if (s.invoices.isNotEmpty)
      Sheet(tx('Invoices', 'الفواتير'), [
        for (final (en, ar) in [('Invoice #', 'رقم الفاتورة'), ('Date', 'التاريخ'), ('Client', 'الزبون'), ('Total', 'المجموع'), ('Paid', 'المدفوع'),
          ('Still owed', 'المتبقي')]) tx(en, ar),
      ], [
        for (final i in s.invoices) [i.no, i.date, s.client(i.clientId)?.name, i.total, i.paid, i.balance],
      ]),
    if (s.expenses.isNotEmpty)
      Sheet(tx('Expenses', 'المصاريف'), [tx('Date', 'التاريخ'), tx('Category', 'النوع'), tx('Amount', 'المبلغ'), tx('Note', 'ملاحظة')], [
        for (final e in s.expenses) [e.date, e.category, e.amount, e.note],
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

String _header(String en, String ar) => tx(en, ar);

/// Issue lines, each with the month it belongs to ([month] is that month's first day).
Sheet issuesSheet(WarehouseStore s, List<(String, Receipt)> list) => Sheet(tx('Issue receipts', 'وصولات الصرف'), [
      for (final (en, ar) in [('Month', 'الشهر'), ('Receipt #', 'رقم الوصل'), ('Date', 'التاريخ'), ('Department', 'القسم'), ('Received by', 'المستلم'),
        ('From', 'من'), ('Code', 'الرمز'), ('Item', 'المادة'), ('Qty', 'الكمية'), ('Unit', 'الوحدة'), ('Note', 'ملاحظة')]) _header(en, ar),
    ], [
      for (final (m, r) in list)
        for (final l in r.lines)
          [
            fmtMonth(m), r.no, r.date, r.department, r.customer,
            r.fromReserve ? tx('Reserve store', 'مخزن الاحتياط') : tx('Main store', 'المخزن الأساسي'),
            l.itemId, s.item(l.itemId)?.name ?? l.itemId, l.qty, s.item(l.itemId)?.unit ?? '', r.note,
          ],
    ]);

Sheet purchasesSheet(WarehouseStore s, List<(String, Purchase)> list) => Sheet(tx('Purchases', 'المشتريات'), [
      for (final (en, ar) in [('Month', 'الشهر'), ('Purchase #', 'رقم الشراء'), ('Date', 'التاريخ'), ('Supplier', 'المجهز'), ('Into', 'إلى'),
        ('Code', 'الرمز'), ('Item', 'المادة'), ('Qty', 'الكمية'), ('Unit', 'الوحدة'), ('Unit price', 'سعر الوحدة'), ('Total', 'المجموع'),
        ('Expiry', 'تاريخ الانتهاء'), ('Lot', 'الوجبة'), ('Note', 'ملاحظة')]) _header(en, ar),
    ], [
      for (final (m, p) in list)
        for (final l in p.lines)
          [
            fmtMonth(m), p.no, p.date, p.supplier, p.toReserve ? tx('Reserve store', 'مخزن الاحتياط') : tx('Main store', 'المخزن الأساسي'),
            l.itemId, s.item(l.itemId)?.name ?? l.itemId, l.qty, s.item(l.itemId)?.unit ?? '', l.unitPrice, l.total, l.expiry, l.lot,
            l.note ?? p.note,
          ],
    ]);

Sheet movesSheet(WarehouseStore s, List<(String, Transfer)> list) => Sheet(tx('Moves', 'النقل'), [
      for (final (en, ar) in [('Month', 'الشهر'), ('#', '#'), ('Date', 'التاريخ'), ('Code', 'الرمز'), ('Item', 'المادة'), ('Qty', 'الكمية'),
        ('Direction', 'الاتجاه')]) _header(en, ar),
    ], [
      for (final (m, t) in list)
        [
          fmtMonth(m), t.no, t.date, t.itemId, s.item(t.itemId)?.name ?? t.itemId, t.qty,
          t.toReserve ? tx('To reserve', 'إلى الاحتياط') : tx('Back to main', 'إلى الأساسي'),
        ],
    ]);

/// What each department took, item by item, with a total line per department.
Sheet departmentsSheet(WarehouseStore s, List<Receipt> receipts) {
  final qty = <String, Map<String, num>>{}, count = <String, int>{};
  for (final r in receipts) {
    final d = (r.department?.trim().isEmpty ?? true) ? tx('No department', 'بدون قسم') : r.department!.trim();
    count[d] = (count[d] ?? 0) + 1;
    final m = qty.putIfAbsent(d, () => {});
    for (final l in r.lines) {
      m[l.itemId] = (m[l.itemId] ?? 0) + l.qty;
    }
  }
  num total(Map<String, num> m) => m.values.fold<num>(0, (a, b) => a + b);
  final depts = qty.keys.toList()..sort((a, b) => total(qty[b]!).compareTo(total(qty[a]!)));
  return Sheet(tx('Departments', 'الأقسام'), [
    for (final (en, ar) in [('Department', 'القسم'), ('Issues', 'وصولات الصرف'), ('Code', 'الرمز'), ('Item', 'المادة'), ('Qty', 'الكمية'),
      ('Unit', 'الوحدة')]) _header(en, ar),
  ], [
    for (final d in depts) ...[
      for (final e in (qty[d]!.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
        [d, count[d], e.key, s.item(e.key)?.name ?? e.key, e.value, s.item(e.key)?.unit ?? ''],
      [d, count[d], null, tx('Total', 'المجموع'), total(qty[d]!), null],
    ],
  ]);
}

/// One month as a workbook: its figures, items, issues, purchases, departments and moves.
List<Sheet> monthSheets(
  WarehouseStore s, {
  required String title,
  required String from,
  required String to,
  required List<MonthRow> rows,
  required Map<String, num> stats,
  required List<Receipt> issues,
  required List<Purchase> purchases,
  required List<Transfer> moves,
  Map<String, num> reserveStart = const {},
  Map<String, num> reserveEnd = const {},
}) {
  num sum(Iterable<num> v) => v.fold<num>(0, (a, b) => a + b);
  final sheets = [
    Sheet(tx('Summary', 'الملخص'), [tx('Month', 'الشهر'), title], [
      [tx('From', 'من'), from],
      [tx('To', 'إلى'), to],
      for (final k in monthStatKeys) [tx(k.$2, k.$3), stats[k.$1]],
      [tx('Issue receipts', 'وصولات الصرف'), issues.length],
      [tx('Purchases', 'المشتريات'), purchases.length],
      [tx('Units spent', 'الوحدات المصروفة'), sum(rows.map((r) => r.issued))],
      [tx('Units received', 'الوحدات الواردة'), sum(rows.map((r) => r.received))],
    ]),
    Sheet(tx('Items', 'المواد'), [
      for (final (en, ar) in [('Code', 'الرمز'), ('Item', 'المادة'), ('Unit', 'الوحدة'), ('Start of month', 'أول الشهر'), ('Received', 'الوارد'),
        ('Issued (spend)', 'المصروف'), ('End of month', 'آخر الشهر'), ('Reserve at start', 'الاحتياط أول الشهر'),
        ('Reserve at end', 'الاحتياط آخر الشهر')]) tx(en, ar),
    ], [
      for (final r in rows)
        [r.itemId, r.name, r.unit, r.opening, r.received, r.issued, r.closing, reserveStart[r.itemId] ?? 0, reserveEnd[r.itemId] ?? 0],
    ]),
    issuesSheet(s, [for (final r in issues) (from, r)]),
    purchasesSheet(s, [for (final p in purchases) (from, p)]),
    departmentsSheet(s, issues),
    movesSheet(s, [for (final t in moves) (from, t)]),
  ];
  return [for (final x in sheets) Sheet(x.name, x.header, x.rows, rightToLeft: isAr)];
}

Future<void> exportMonthExcel(WarehouseStore s, String file, List<Sheet> sheets) =>
    downloadFile(file, buildXlsx(sheets), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
