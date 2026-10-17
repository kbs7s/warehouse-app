import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_app/l10n.dart';
import 'package:warehouse_app/main.dart';
import 'package:warehouse_app/month.dart';
import 'package:warehouse_app/models.dart';
import 'package:warehouse_app/pdf.dart';
import 'package:warehouse_app/store.dart';

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

  testWidgets('stock screen lists items and filters low stock', (t) async {
    ipad(t);
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeShell(store: store)));
    await go(t, 'Stock');
    expect(find.text('اسفنجة تعقيم'), findsOneWidget);
    await t.tap(find.textContaining('Low '));
    await t.pump();
    expect(find.text('شرشف لاستيك مريض'), findsOneWidget);
    expect(find.text('اسفنجة تعقيم'), findsNothing);
  });

  testWidgets('new receipt reduces stock', (t) async {
    ipad(t);
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeShell(store: store)));
    await go(t, 'Issue');
    await t.tap(find.text('Issue supplies'));
    await t.pumpAndSettle();
    await t.enterText(find.widgetWithText(TextField, 'Department'), 'NICU');
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

  testWidgets('issue form offers recent departments as one-tap chips', (t) async {
    ipad(t);
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeShell(store: store)));
    await go(t, 'Issue');
    await t.tap(find.text('Issue supplies'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ActionChip, 'NICU'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'NICU'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);
  });

  testWidgets('invoice for a new client takes stock out and records a payment', (t) async {
    ipad(t);
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeShell(store: store)));
    await go(t, 'Money', 'Invoices');
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
      await t.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeShell(store: store)));
      expect(find.text('Issue to department'), findsOneWidget);
      expect(find.text('Reorder now'), findsOneWidget);
      for (final (section, pages) in [
        ('Issue', <String>[]),
        ('Stock', ['Items', 'Reorder', 'Purchases', 'Reports']),
        ('Money', ['Overview', 'Invoices', 'Clients', 'Expenses', 'Supplier bills']),
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
      for (final section in ['الصرف', 'المخزون', 'الشهر', 'المالية', 'الرئيسية']) {
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
    expect(find.text('Since 1 Sep 2026'), findsOneWidget);
    await t.tap(find.text('Close month & start new'));
    await t.pumpAndSettle();
    expect(find.text('1 Sep 2026 – 30 Sep 2026'), findsOneWidget);
    await t.tap(find.widgetWithText(FilledButton, 'Close month'));
    await t.pumpAndSettle();
    expect(store.monthCloses.single.from, '2026-09-01');
    expect(find.text('September 2026'), findsOneWidget);
    expect(find.text('Since 1 Oct 2026'), findsOneWidget);
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
}

String todayIsoForTest() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
}
