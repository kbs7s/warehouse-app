import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_app/changes.dart';
import 'package:warehouse_app/export.dart';
import 'package:warehouse_app/models.dart';
import 'package:warehouse_app/month.dart';
import 'package:warehouse_app/store.dart';

WarehouseStore seeded() {
  final s = WarehouseStore(null);
  s.applyJson(jsonDecode(File('seed/app_seed.json').readAsStringSync()) as Map<String, dynamic>, save: false);
  return s;
}

WarehouseStore copyOf(WarehouseStore s) =>
    WarehouseStore(null)..applyJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>, save: false);

void main() {
  test('closing a month starts fresh: records archived, numbers restart, stock carries over', () {
    final s = seeded();
    s.setOpenMonthStart('2026-10-01');
    s.saveReceipt(Receipt(no: s.nextReceiptNo, date: '2026-10-05', department: 'NICU', lines: [ReceiptLine(itemId: 'P001', qty: 10)]));
    s.transfer('P001', 30, toReserve: true, date: '2026-10-06');
    s.savePurchase(Purchase(no: s.nextPurchaseNo, date: '2026-10-07', supplier: 'Ali', lines: [PurchaseLine(itemId: 'P013', qty: 5, total: 50000)], paidLog: []));
    final stock = {for (final i in s.items) i.id: (s.stock(i.id).qty, s.stock(i.id).reserve)};
    final issuesBefore = s.receipts.length, purchasesBefore = s.purchases.length;
    final spentOct = s.spentThisMonth['P001']!;
    final yearBefore = s.spentThisYear['P001']!;
    final debt = s.weOwe;

    final m = s.closeMonth(to: '2026-10-31', stats: {'operations': 120, 'cath': 14});

    // Everything up to the close moved into the month; the open lists are empty.
    expect(m.fresh, isTrue);
    expect(m.issueList, hasLength(issuesBefore));
    expect(m.purchaseList, hasLength(purchasesBefore));
    expect(m.transferList, hasLength(1));
    expect(s.receipts, isEmpty);
    expect(s.purchases, isEmpty);
    expect(s.transfers, isEmpty);
    expect(s.nextReceiptNo, 1);
    expect(s.nextPurchaseNo, 1);
    expect(s.nextTransferNo, 1);
    // Spend starts from zero; the year still counts the closed month.
    expect(s.spentThisMonth['P001'] ?? 0, 0);
    expect(s.spentThisYear['P001'], yearBefore);
    expect(m.rows.firstWhere((r) => r.itemId == 'P001').issued, spentOct);
    // Stock in both stores is unchanged and is now the opening stock.
    for (final i in s.items) {
      expect((s.stock(i.id).qty, s.stock(i.id).reserve), stock[i.id], reason: i.id);
    }
    expect(s.item('P001')!.openingReserve, 30);
    expect(m.reserveEnd['P001'], 30);
    // The unpaid purchase is still owed, as a carried-over bill.
    expect(s.weOwe, debt);
    expect(s.owedTo('Ali'), 50000);
    expect(s.payments.where((b) => b.carriedFrom == '2026-10-01'), hasLength(1));
    expect(m.stats, {'operations': 120, 'cath': 14});

    // A new month's issue starts at number 1 and takes from the carried-over stock.
    s.saveReceipt(Receipt(no: s.nextReceiptNo, date: '2026-11-02', department: 'ER', lines: [ReceiptLine(itemId: 'P001', qty: 4)]));
    expect(s.receipts.single.no, 1);
    expect(s.stock('P001').qty, stock['P001']!.$1 - 4);
    expect(s.allReceipts.length, issuesBefore + 1);

    // Paying the supplier settles the carried bill.
    s.paySupplier('Ali', 20000, date: '2026-11-03');
    expect(s.owedTo('Ali'), 30000);

    // Survives a backup round trip.
    final c = copyOf(s);
    expect(c.monthCloses.single.issueList, hasLength(issuesBefore));
    expect(c.monthCloses.single.stats['operations'], 120);
    expect(c.stock('P001').qty, s.stock('P001').qty);
    expect(c.stock('P001').reserve, 30);
  });

  test('stats can be filled in later; the month workbook has every part', () {
    final s = seeded();
    s.setOpenMonthStart('2026-09-01');
    final m = s.closeMonth(to: '2026-10-31');
    expect(m.statsMissing, isTrue);
    s.setMonthStats(m, {'operations': 1, 'cath': 2, 'nicu': 3, 'insurance': 4});
    expect(s.monthCloses.single.statsMissing, isFalse);
    final sheets = monthSheets(s,
        title: 'Sep', from: m.from, to: m.to, rows: m.rows, stats: m.stats, issues: m.issueList, purchases: m.purchaseList, moves: m.transferList);
    expect(sheets.map((x) => x.name), ['Summary', 'Items', 'Issue receipts', 'Purchases', 'Departments', 'Moves']);
    expect(sheets.first.rows.any((r) => r.first == 'Premature (NICU) admissions' && r.last == 3), isTrue);
  });

  test('reopening puts the month back, unless the new month has records', () {
    final s = seeded();
    s.setOpenMonthStart('2026-09-01');
    final issues = s.receipts.length;
    final opening = s.item('P001')!.openingQty;
    final qty = s.stock('P001').qty;
    s.closeMonth(to: '2026-10-31');
    expect(s.item('P001')!.openingQty, isNot(opening));

    s.saveReceipt(Receipt(no: 1, date: '2026-11-02', department: 'ER', lines: [ReceiptLine(itemId: 'P001', qty: 1)]));
    expect(s.reopenBlocker(), isNotNull);
    s.reopenLastMonth();
    expect(s.monthCloses, hasLength(1), reason: 'blocked');
    s.deleteReceipt(1);

    expect(s.reopenBlocker(), isNull);
    s.reopenLastMonth();
    expect(s.monthCloses, isEmpty);
    expect(s.receipts, hasLength(issues));
    expect(s.item('P001')!.openingQty, opening);
    expect(s.stock('P001').qty, qty);
    expect(s.openMonthStart, '2026-09-01');
    expect(s.payments.where((b) => b.carriedFrom != null), isEmpty);
  });

  test('reserve-only items live in the reserve and stay out of the main store lists', () {
    final s = seeded();
    s.saveItem(Item(id: 'R001', name: 'Adrenaline', unit: 'amp', openingQty: 20, openingReserve: 20, reserveOnly: true));
    expect(s.stock('R001').reserve, 20);
    expect(s.stock('R001').qty, 0);
    expect(s.stockList.any((x) => x.item.id == 'R001'), isFalse);
    expect(s.reserveStockList.any((x) => x.item.id == 'R001'), isTrue);

    s.savePurchase(Purchase(no: s.nextPurchaseNo, date: '2026-10-07', toReserve: true, lines: [PurchaseLine(itemId: 'R001', qty: 10)]));
    expect(s.stock('R001').reserve, 30);
    s.saveReceipt(Receipt(no: s.nextReceiptNo, date: '2026-10-08', department: 'ER', fromReserve: true, lines: [ReceiptLine(itemId: 'R001', qty: 3)]));
    expect(s.stock('R001').reserve, 27);
    expect(s.stock('R001').qty, 0);

    final c = copyOf(s);
    expect(c.item('R001')!.reserveOnly, isTrue);
    expect(c.stock('R001').reserve, 27);

    // Closing the month keeps it in the reserve.
    s.setOpenMonthStart('2026-10-01');
    s.closeMonth(to: '2026-10-31');
    expect(s.stock('R001').reserve, 27);
    expect(s.item('R001')!.openingReserve, 27);
  });

  test('the changes list shows a close as one line, not every archived record', () {
    final s = seeded();
    s.setOpenMonthStart('2026-09-01');
    final before = copyOf(s).toJson();
    s.closeMonth(to: '2026-10-31');
    final after = copyOf(s).toJson();
    final found = findChanges(before, after, by: 'Karar');
    expect(found.map((c) => c.en), ['Month closed (9/2026)']);
  });
}
