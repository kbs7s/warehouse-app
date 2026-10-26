import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_app/l10n.dart';
import 'package:warehouse_app/expiry.dart';
import 'package:warehouse_app/main.dart';
import 'package:warehouse_app/month.dart';
import 'package:warehouse_app/models.dart';
import 'package:warehouse_app/pdf.dart';
import 'package:warehouse_app/screens/departments_screen.dart';
import 'package:warehouse_app/store.dart';
import 'package:warehouse_app/ui.dart';

void main() {
  late WarehouseStore store;
  setUp(() {
    store = WarehouseStore(null)
      ..applyJson(jsonDecode(File('seed/app_seed.json').readAsStringSync()) as Map<String, dynamic>,
          save: false);
  });

  void ipad(WidgetTester t) {
    t.view.physicalSize = const Size(2360, 1640);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
  }

  void phone(WidgetTester t) {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
  }

  Future<void> go(WidgetTester t, String section, [String? page]) async {
    await t.tap(find.text(section).last);
    await t.pumpAndSettle();
    if (page != null) {
      await t.tap(find.widgetWithText(ChoiceChip, page));
      await t.pumpAndSettle();
    }
  }

  testWidgets('stock screen lists items and filters out-of-stock ones', (t) async {
    ipad(t);
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeShell(store: store)));
    await go(t, 'Stock');
    expect(find.text('اسفنجة تعقيم'), findsOneWidget);
    expect(find.textContaining('Low '), findsNothing);
    expect(find.text('Min'), findsNothing);
    await t.tap(find.textContaining('Out '));
    await t.pump();
    expect(find.text('اسفنجة تعقيم'), findsNothing);
  });

  testWidgets('new receipt reduces stock', (t) async {
    ipad(t);
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeShell(store: store)));
    await go(t, 'Issue');
    await t.tap(find.text('Issue supplies'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ChoiceChip, 'NICU'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Note'), findsNothing);
    await t.tap(find.text('Add item'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Type part of the item name'), 'اسفنجة');
    await t.pumpAndSettle();
    await t.tap(find.text('اسفنجة تعقيم'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Qty'), '10');
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await t.pumpAndSettle();
    expect(store.receipts.last.no, 21);
    expect(store.stock('P001').qty, 500);
  });

  testWidgets('issue form picks the department from the Settings list only', (t) async {
    ipad(t);
    store.renameDepartment('NICU', 'الخدج');
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeShell(store: store)));
    await go(t, 'Issue');
    await t.tap(find.text('Issue supplies'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Department'), findsNothing);
    expect(find.widgetWithText(ChoiceChip, 'NICU'), findsNothing);
    await t.tap(find.widgetWithText(ChoiceChip, 'الخدج'));
    await t.pumpAndSettle();
    expect(t.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'الخدج')).selected, isTrue);
  });

  testWidgets('equipment records a purchase and an issue to a department', (t) async {
    ipad(t);
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeShell(store: store)));
    await go(t, 'Equipment');
    final e = store.equipment.first;
    final before = e.nowQty;
    await t.tap(find.text('Purchase').first);
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Quantity'), '3');
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await t.pumpAndSettle();
    expect(store.equipment.first.nowQty, before + 3);
    await t.tap(find.widgetWithIcon(FilledButton, Icons.outbox_outlined).first);
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Quantity'), '2');
    await t.tap(find.widgetWithText(ChoiceChip, 'NICU'));
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await t.pumpAndSettle();
    expect(store.equipment.first.nowQty, before + 1);
    expect(store.equipment.first.moves.last.party, 'NICU');
    expect(t.takeException(), isNull);
  });

  testWidgets('invoice for a new client takes stock out and records a payment', (t) async {
    ipad(t);
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeShell(store: store)));
    await go(t, 'Settings');
    await t.ensureVisible(find.text('Sales, clients and expenses', skipOffstage: false));
    await t.pumpAndSettle();
    await t.tap(find.text('Sales, clients and expenses'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ChoiceChip, 'Invoices'));
    await t.pumpAndSettle();
    await t.tap(find.text('New invoice').first);
    await t.pumpAndSettle();
    await t.tap(find.text('Choose client'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Find a client'), 'Al Noor Clinic');
    await t.pumpAndSettle();
    await t.tap(find.text('New client "Al Noor Clinic"'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Save').last);
    await t.pumpAndSettle();
    expect(find.text('Al Noor Clinic'), findsOneWidget);

    await t.tap(find.text('Add stock item'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Type part of the item name'), 'اسفنجة');
    await t.pumpAndSettle();
    await t.tap(find.text('اسفنجة تعقيم'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Qty'), '5');
    await t.enterText(find.widgetWithText(TextField, 'Price each (IQD)'), '2000');
    await t.pumpAndSettle();
    expect(find.text('10,000 IQD'), findsWidgets);
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await t.pumpAndSettle();

    final inv = store.invoices.single;
    expect(inv.total, 10000);
    expect(store.client(inv.clientId)!.name, 'Al Noor Clinic');
    expect(store.stock('P001').qty, 505);
    expect(inv.status(todayIsoForTest()), InvoiceStatus.unpaid);

    await t.tap(find.text('Al Noor Clinic'));
    await t.pumpAndSettle();
    await t.tap(find.text('Record payment'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Amount received (IQD)'), '4000');
    await t.tap(find.text('Save payment'));
    await t.pumpAndSettle();
    expect(inv.paid, 4000);
    expect(store.owedToUs, 6000);
    expect(find.text('Part paid'), findsWidgets);
  });

  for (final (name, setSize) in [('phone', phone), ('iPad', ipad)]) {
    testWidgets('every section opens without layout errors on $name', (t) async {
      setSize(t);
      store.saveClient(Client(id: 'c1', name: 'مستشفى الكفيل'));
      store.saveInvoice(Invoice(no: 1, date: '2026-10-02', dueDate: '2026-10-05', clientId: 'c1', lines: [
        InvoiceLine(itemId: 'P001', qty: 3, unitPrice: 2500),
        InvoiceLine(description: 'Delivery', qty: 1, unitPrice: 5000),
      ]));
      store.saveExpense(Expense(id: 'e1', date: '2026-10-03', category: 'Rent', amount: 300000));
      store.saveExpiry('P001', ExpiryBatch(date: '2026-01-10', qty: 20, lot: 'A1'));
      store.saveExpiry('P013', ExpiryBatch(date: isoDate(DateTime.now().add(const Duration(days: 20)))));
      await t.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeShell(store: store)));
      expect(find.text('Issue to department'), findsOneWidget);
      expect(find.text('Reorder now', skipOffstage: false), findsOneWidget);
      for (final (section, pages) in [
        ('Issue', <String>[]),
        ('Stock', ['Items', 'Reorder', 'Expiry', 'Count', 'Reports']),
        ('Purchases', ['Purchases', 'Payments', 'Older bills']),
        ('Month', <String>[]),
        ('Home', <String>[]),
      ]) {
        await go(t, section);
        for (final p in pages.skip(1)) {
          await t.ensureVisible(find.widgetWithText(ChoiceChip, p, skipOffstage: false));
          await t.pumpAndSettle();
          await t.tap(find.widgetWithText(ChoiceChip, p));
          await t.pumpAndSettle();
        }
      }
      expect(t.takeException(), isNull);
    });
  }

  for (final (name, setSize) in [('phone', phone), ('iPad', ipad)]) {
    testWidgets('Arabic interface opens every section right to left on $name', (t) async {
      setSize(t);
      isAr = true;
      addTearDown(() => isAr = false);
      store.saveExpense(Expense(id: 'e1', date: '2026-10-03', category: 'Rent', amount: 300000));
      await t.pumpWidget(MaterialApp(
        theme: buildTheme(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('en'), Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: HomeShell(store: store),
      ));
      await t.pumpAndSettle();
      expect(find.text('صرف إلى قسم'), findsWidgets);
      expect(Directionality.of(t.element(find.byType(HomeShell))), TextDirection.rtl);
      for (final section in ['الصرف', 'المخزون', 'الشهر', 'المشتريات', 'الرئيسية']) {
        await t.tap(find.text(section).last);
        await t.pumpAndSettle();
      }
      expect(t.takeException(), isNull);
    });
  }

  test('month spend starts again after closing the month, stock carries over', () {
    store.setOpenMonthStart('2026-09-01');
    final before = store.stock('P001').qty;
    final sept = store.spentThisMonth['P001'] ?? 0;
    expect(sept, greaterThan(0));
    final rows = store.monthRows('2026-09-01', '2026-09-30');
    final p001 = rows.firstWhere((r) => r.itemId == 'P001');
    expect(p001.issued, sept);
    expect(p001.closing, before); // nothing after September in the seed

    final m = store.closeMonth(to: '2026-09-30');
    expect(m.rows.firstWhere((r) => r.itemId == 'P001').issued, sept);
    expect(store.openMonthStart, '2026-10-01');
    expect(store.spentThisMonth['P001'] ?? 0, 0);
    expect(store.stock('P001').qty, before);
    expect(store.spentThisYear['P001'], greaterThanOrEqualTo(sept));

    // Saved in backups, and reopening takes the close back.
    final copy = WarehouseStore(null)..applyJson(jsonDecode(jsonEncode(store.toJson())) as Map<String, dynamic>, save: false);
    expect(copy.monthCloses.single.to, '2026-09-30');
    expect(copy.openMonthStart, '2026-10-01');
    store.reopenLastMonth();
    expect(store.monthCloses, isEmpty);
    expect(store.openMonthStart, '2026-09-01');
  });

  testWidgets('month page closes the month from the button', (t) async {
    ipad(t);
    store.setOpenMonthStart('2026-09-01');
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeShell(store: store)));
    await go(t, 'Month');
    expect(find.text('9/2026'), findsOneWidget);
    await t.tap(find.text('Close month & start new'));
    await t.pumpAndSettle();
    expect(find.text('1 Sep 2026 – 30 Sep 2026'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Close month'));
    await t.pumpAndSettle();
    expect(store.monthCloses.single.from, '2026-09-01');
    expect(find.text('9/2026'), findsWidgets);
    expect(find.text('10/2026'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test('expiry alerts: expired, soon, later, and out-of-stock items left out', () {
    store.saveExpiry('P001', ExpiryBatch(date: '2026-10-10', qty: 5));
    store.saveExpiry('P001', ExpiryBatch(date: '2026-11-01'));
    store.saveExpiry('P001', ExpiryBatch(date: '2027-12-01'));
    store.saveExpiry('P003', ExpiryBatch(date: '2026-10-01')); // P003 has nothing in stock
    final l = store.expiryList(today: '2026-10-18');
    expect([for (final e in l) e.level], [ExpiryLevel.expired, ExpiryLevel.soon, ExpiryLevel.later]);
    expect(l.first.daysLeft, -8);
    expect(l[1].daysLeft, 14);
    expect(store.expiryList(all: true, today: '2026-10-18').length, 4);
    final copy = WarehouseStore(null)..applyJson(jsonDecode(jsonEncode(store.toJson())) as Map<String, dynamic>, save: false);
    expect(copy.item('P001')!.expiries.map((e) => e.date), ['2026-10-10', '2026-11-01', '2027-12-01']);
    expect(copy.item('P001')!.expiries.first.qty, 5);
  });

  testWidgets('departments page shows what each department took', (t) async {
    ipad(t);
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeShell(store: store)));
    await go(t, 'Issue', 'Departments');
    await t.tap(find.widgetWithText(ChoiceChip, 'All time'));
    await t.pumpAndSettle();
    final top = departmentUse(store, '0000-01-01', '9999-12-31').first;
    await t.tap(find.text(top.name).first);
    await t.pumpAndSettle();
    expect(find.text('Items taken'), findsOneWidget);
    final (id, qty) = top.qty.entries.reduce((a, b) => a.value >= b.value ? a : b).let((e) => (e.key, e.value));
    expect(find.text(store.item(id)!.name), findsWidgets);
    expect(find.textContaining(fmtQty(qty)), findsWidgets);
  });

  test('departments can be added, renamed and removed', () {
    expect(store.addDepartment('Pharmacy'), isTrue);
    expect(store.addDepartment('Pharmacy'), isFalse);
    final used = store.receipts.firstWhere((r) => r.department != null).department!;
    final n = store.receipts.where((r) => r.department == used).length;
    store.renameDepartment(used, 'Renamed dept');
    expect(store.receipts.where((r) => r.department == 'Renamed dept').length, n);
    expect(store.departments, contains('Renamed dept'));
    store.removeDepartment('Pharmacy');
    expect(store.departments, isNot(contains('Pharmacy')));
  });

  testWidgets('new item form on a phone saves with a unit chip', (t) async {
    phone(t);
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeShell(store: store)));
    await go(t, 'Stock');
    await t.tap(find.text('New item'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextFormField, 'Item name'), 'كمامة جديدة');
    final unit = store.items.first.unit;
    await t.tap(find.widgetWithText(ChoiceChip, unit).first);
    await t.pump();
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await t.pumpAndSettle();
    expect(store.items.last.name, 'كمامة جديدة');
    expect(store.items.last.unit, unit);
    expect(t.takeException(), isNull);
  });

  testWidgets('expiry date is added from the item page and shows on the Expiry page', (t) async {
    ipad(t);
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeShell(store: store)));
    await go(t, 'Stock');
    await t.tap(find.text('اسفنجة تعقيم'));
    await t.pumpAndSettle();
    await t.tap(find.text('No expiry dates entered.'));
    await t.pumpAndSettle();
    await t.tap(find.text('Tap to choose'));
    await t.pumpAndSettle();
    await t.tap(find.text('OK'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Lot / batch number (optional)'), 'L7');
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await t.pumpAndSettle();
    expect(store.item('P001')!.expiries.single.lot, 'L7');
    expect(find.textContaining('lot L7'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test('purchase expiry dates go on the item and follow edits and deletes', () {
    final before = store.item('P001')!.expiries.length;
    final p = Purchase(no: 90, date: '2026-10-20', supplier: 'زانيار', lines: [
      PurchaseLine(itemId: 'P001', qty: 50, unitPrice: 1000, expiry: '2027-05-01', lot: 'B9'),
      PurchaseLine(itemId: 'P013', qty: 5, unitPrice: 2000),
    ], paidLog: []);
    store.savePurchase(p);
    expect(store.item('P001')!.expiries.length, before + 1);
    expect(store.item('P001')!.expiries.last.lot, 'B9');
    expect(store.item('P001')!.expiries.last.qty, 50);

    store.savePurchase(Purchase(no: 90, date: '2026-10-20', supplier: 'زانيار', lines: [
      PurchaseLine(itemId: 'P001', qty: 40, unitPrice: 1000, expiry: '2027-06-01', lot: 'B9'),
    ], paidLog: []));
    expect(store.item('P001')!.expiries.where((b) => b.lot == 'B9').single.date, '2027-06-01');

    store.deletePurchase(90);
    expect(store.item('P001')!.expiries.length, before);
  });

  test('paying a supplier settles the oldest purchases first', () {
    final owedBefore = store.weOwe;
    store.savePurchase(Purchase(no: 91, date: '2026-10-01', supplier: 'S1', lines: [PurchaseLine(itemId: 'P001', qty: 10, unitPrice: 1000)], paidLog: []));
    store.savePurchase(Purchase(no: 92, date: '2026-10-05', supplier: 'S1', lines: [PurchaseLine(itemId: 'P001', qty: 5, unitPrice: 1000)], paidLog: []));
    expect(store.owedTo('S1'), 15000);
    expect(store.weOwe, owedBefore + 15000);
    expect(store.paySupplier('S1', 12000, date: '2026-10-10'), 0);
    final a = store.purchases.firstWhere((p) => p.no == 91), b = store.purchases.firstWhere((p) => p.no == 92);
    expect(a.settled, isTrue);
    expect(b.paid, 2000);
    expect(b.owed, 3000);

    // Survives a backup, and older purchases without payment records owe nothing.
    final copy = WarehouseStore(null)..applyJson(jsonDecode(jsonEncode(store.toJson())) as Map<String, dynamic>, save: false);
    expect(copy.owedTo('S1'), 3000);
    expect(Purchase.fromJson({'no': 1, 'lines': [{'itemId': 'P001', 'qty': 2, 'total': 500}]}).owed, 0);
  });

  for (final (name, setSize) in [('phone', phone), ('iPad', ipad)]) {
    testWidgets('purchase with expiry date and a part payment on $name', (t) async {
      setSize(t);
      await t.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeShell(store: store)));
      await go(t, 'Purchases');
      await t.tap(find.text('New purchase'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, 'Supplier'), 'زانيار');
      await t.tap(find.text('Add item'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, 'Type part of the item name'), 'اسفنجة');
      await t.pumpAndSettle();
      await t.tap(find.text('اسفنجة تعقيم'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, 'Qty'), '10');
      await t.enterText(find.widgetWithText(TextField, 'Unit price'), '1500');
      await t.pumpAndSettle();
      await t.tap(find.text('Expiry date'));
      await t.pumpAndSettle();
      await t.tap(find.text('OK'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, 'Batch / lot'), 'Z1');
      await t.ensureVisible(find.text('Add payment'));
      await t.pumpAndSettle();
      await t.tap(find.text('Add payment'));
      await t.pumpAndSettle();
      await t.enterText(find.widgetWithText(TextField, 'Amount paid (IQD)'), '5000');
      await t.tap(find.widgetWithText(FilledButton, 'Add'));
      await t.pumpAndSettle();
      expect(find.text('10,000 IQD'), findsOneWidget); // still owed
      await t.tap(find.widgetWithText(FilledButton, 'Save'));
      await t.pumpAndSettle();

      final p = store.purchases.last;
      expect(p.supplier, 'زانيار');
      expect(p.total, 15000);
      expect(p.paid, 5000);
      expect(p.lines.single.lot, 'Z1');
      expect(store.item('P001')!.expiries.where((b) => b.lot == 'Z1'), hasLength(1));
      expect(find.text('Owed 10,000 IQD'), findsOneWidget);

      await t.tap(find.widgetWithText(ChoiceChip, 'Payments'));
      await t.pumpAndSettle();
      await t.tap(find.text('زانيار').first);
      await t.pumpAndSettle();
      await t.tap(find.text('Record payment'));
      await t.pumpAndSettle();
      await t.tap(find.text('All of it'));
      await t.tap(find.widgetWithText(FilledButton, 'Save'));
      await t.pumpAndSettle();
      expect(p.settled, isTrue);
      expect(store.owedTo('زانيار'), 0);
      expect(t.takeException(), isNull);
    });
  }

  test('reserve store: moves and emergency issues keep the two stores apart', () {
    final total = store.stock('P001').total, main = store.stock('P001').qty;
    store.transfer('P001', 100, toReserve: true, date: '2026-10-20');
    expect(store.stock('P001').reserve, 100);
    expect(store.stock('P001').qty, main - 100);
    expect(store.stock('P001').total, total);
    store.saveReceipt(Receipt(no: 500, date: '2026-10-21', department: 'NICU', lines: [ReceiptLine(itemId: 'P001', qty: 30)], fromReserve: true));
    expect(store.stock('P001').reserve, 70);
    expect(store.stock('P001').qty, main - 100);
    store.transfer('P001', 20, toReserve: false, date: '2026-10-22');
    expect(store.stock('P001').reserve, 50);
    expect(store.stock('P001').qty, main - 80);
    final copy = WarehouseStore(null)..applyJson(jsonDecode(jsonEncode(store.toJson())) as Map<String, dynamic>, save: false);
    expect(copy.stock('P001').reserve, 50);
    expect(copy.receipts.last.fromReserve, isTrue);
  });

  test('reserve count: shortfall is an emergency issue, extras go into the reserve, main store untouched', () {
    store.transfer('P001', 50, toReserve: true, date: '2026-10-20');
    store.transfer('P013', 10, toReserve: true, date: '2026-10-20');
    final mainA = store.stock('P001').qty, mainB = store.stock('P013').qty;
    store.setStockCount(StockCount(started: '2026-10-26', items: ['P001', 'P013'], counted: {'P001': 45, 'P013': 12}), reserve: true);
    expect(store.stockCount, isNull);
    final copy = WarehouseStore(null)..applyJson(jsonDecode(jsonEncode(store.toJson())) as Map<String, dynamic>, save: false);
    expect(copy.reserveCount!.items, ['P001', 'P013']);
    final made = store.finishStockCount({'P001': 'NICU'}, date: '2026-10-26', label: 'Reserve count', reserve: true);
    expect(made.single.fromReserve, isTrue);
    expect(store.stock('P001').reserve, 45);
    expect(store.stock('P013').reserve, 12);
    expect(store.stock('P001').qty, mainA);
    expect(store.stock('P013').qty, mainB);
    expect(store.reserveCount, isNull);
  });

  test('stock count issues the shortfall to the chosen departments and adds extras', () {
    final a = store.stock('P001').qty, b = store.stock('P013').qty, c = store.stock('P005').qty;
    store.setStockCount(StockCount(started: '2026-10-22', counted: {'P001': a - 10, 'P013': b - 4, 'P005': c + 2}));
    final made = store.finishStockCount({'P001': 'NICU', 'P013': 'Lab'}, date: '2026-10-22', label: 'Stock count');
    expect(made, hasLength(2));
    expect(store.stock('P001').qty, a - 10);
    expect(store.stock('P013').qty, b - 4);
    expect(store.stock('P005').qty, c + 2);
    expect(store.receipts.firstWhere((r) => r.department == 'NICU' && r.note == 'Stock count').lines.single.qty, 10);
    expect(store.stockCount, isNull);
  });

  testWidgets('stock count goes item by item and saves the shortfall', (t) async {
    ipad(t);
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeShell(store: store)));
    await go(t, 'Stock', 'Count');
    await t.tap(find.text('Start count'));
    await t.pumpAndSettle();
    final first = ([...store.activeItems]..sort((a, b) => a.id.compareTo(b.id))).first;
    final had = store.stock(first.id).qty;
    expect(find.text(first.name), findsOneWidget);
    await t.enterText(find.widgetWithText(TextField, 'Counted now'), '${had - 5}');
    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(store.stockCount!.counted[first.id], had - 5);
    await t.tap(find.text('Same as app'));
    await t.pumpAndSettle();
    expect(find.text('2 of ${store.activeItems.length} counted'), findsOneWidget);
    await t.tap(find.text('Finish and review differences'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ChoiceChip, 'NICU'));
    await t.pumpAndSettle();
    await t.tap(find.text('Save count'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(FilledButton, 'Save').last);
    await t.pumpAndSettle();
    expect(store.stock(first.id).qty, had - 5);
    expect(store.receipts.last.department, 'NICU');
    expect(store.stockCount, isNull);
    expect(t.takeException(), isNull);
  });

  testWidgets('reserve page moves stock and opens an emergency issue', (t) async {
    ipad(t);
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeShell(store: store)));
    await go(t, 'Reserve');
    await t.tap(find.text('Move to reserve'));
    await t.pumpAndSettle();
    await t.tap(find.text('Choose item'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Type part of the item name'), 'اسفنجة');
    await t.pumpAndSettle();
    await t.tap(find.text('اسفنجة تعقيم'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Quantity'), '40');
    await t.tap(find.widgetWithText(FilledButton, 'Move'));
    await t.pumpAndSettle();
    expect(store.stock('P001').reserve, 40);
    expect(find.text('اسفنجة تعقيم'), findsOneWidget);
    await t.tap(find.text('Emergency issue'));
    await t.pumpAndSettle();
    expect(find.text('Emergency issue (reserve)'), findsOneWidget);
    await t.tap(find.widgetWithText(ChoiceChip, 'NICU'));
    await t.tap(find.text('Add item'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Type part of the item name'), 'اسفنجة');
    await t.pumpAndSettle();
    await t.tap(find.text('اسفنجة تعقيم'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Qty'), '15');
    await t.tap(find.widgetWithText(FilledButton, 'Save'));
    await t.pumpAndSettle();
    expect(store.stock('P001').reserve, 25);
    expect(store.receipts.last.fromReserve, isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets('appearance: night mode, colour and text size are picked in Settings', (t) async {
    ipad(t);
    await t.pumpWidget(BusinessApp(store: store));
    await t.pumpAndSettle();
    await go(t, 'Settings');
    await t.tap(find.text('Night'));
    await t.pumpAndSettle();
    expect(store.themeMode, 'dark');
    expect(Theme.of(t.element(find.byType(HomeShell))).brightness, Brightness.dark);
    await t.tap(find.bySemanticsLabel('Purple'));
    await t.pumpAndSettle();
    expect(store.accent, 2);
    await t.ensureVisible(find.text('Large', skipOffstage: false));
    await t.pumpAndSettle();
    await t.tap(find.text('Large'));
    await t.pumpAndSettle();
    expect(store.textSize, 1.15);
    expect(t.takeException(), isNull);
  });

  test('receipt and invoice PDFs build with Arabic names', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes = await buildReceiptPdf(store, store.receipts.firstWhere((r) => r.no == 20));
    expect(bytes.length, greaterThan(10000));
    File('build/receipt-20.pdf')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    store.saveClient(Client(id: 'c1', name: 'مستشفى الكفيل', phone: '0770 000 0000'));
    final inv = Invoice(no: 7, date: '2026-10-02', clientId: 'c1', discount: 500, lines: [
      InvoiceLine(itemId: 'P001', qty: 3, unitPrice: 2500),
      InvoiceLine(description: 'توصيل', qty: 1, unitPrice: 5000),
    ]);
    store.saveInvoice(inv);
    final pdf = await buildInvoicePdf(store, inv);
    expect(pdf.length, greaterThan(10000));
    File('build/invoice-7.pdf').writeAsBytesSync(pdf);
  });

  testWidgets('weekly backup reminder shows on Home until snoozed or backed up', (t) async {
    ipad(t);
    store.lastBackupAt = DateTime.now().subtract(const Duration(days: 9)).toIso8601String();
    expect(store.backupDue, isTrue);
    await t.pumpWidget(BusinessApp(store: store));
    await t.pumpAndSettle();
    expect(find.text('Back up now'), findsOneWidget);
    await t.tap(find.text('Tomorrow'));
    await t.pumpAndSettle();
    expect(find.text('Back up now'), findsNothing);
    expect(store.backupDue, isFalse);
    store.backupSnooze = null;
    store.markBackedUp();
    expect(store.backupDue, isFalse);
    store.lastBackupAt = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
    expect(store.backupDue, isTrue);
    expect(t.takeException(), isNull);
  });

  test('department report PDF builds in English and Arabic', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final en = await buildDepartmentsPdf(store, '0000-01-01', '9999-12-31', 'Department report');
    expect(en.length, greaterThan(10000));
    isAr = true;
    final ar = await buildDepartmentsPdf(store, '0000-01-01', '9999-12-31', 'تقرير الأقسام');
    isAr = false;
    expect(ar.length, greaterThan(10000));
    File('build/departments.pdf')
      ..createSync(recursive: true)
      ..writeAsBytesSync(ar);
  });
}

String todayIsoForTest() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);

}
