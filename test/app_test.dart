import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:warehouse_app/claude.dart';
import 'package:warehouse_app/main.dart';
import 'package:warehouse_app/models.dart';
import 'package:warehouse_app/pdf.dart';
import 'package:warehouse_app/screens/assistant_screen.dart';
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
        ('Assistant', <String>[]),
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

  testWidgets('assistant sends the question with business data and shows the answer', (t) async {
    ipad(t);
    late Map<String, dynamic> sent;
    final client = ClaudeClient('sk-test', client: MockClient((req) async {
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      expect(req.headers['anthropic-dangerous-direct-browser-access'], 'true');
      return http.Response(jsonEncode({
        'content': [
          {'type': 'text', 'text': 'You made a small profit this month.'}
        ]
      }), 200);
    }));
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: AssistantScreen(store: store, client: client)));
    await t.tap(find.text('How did the business do this month?'));
    await t.pumpAndSettle();
    expect(find.text('You made a small profit this month.'), findsOneWidget);
    expect(sent['model'], ClaudeClient.model);
    expect(sent['system'] as String, contains('Stock (code, name'));
    expect((sent['messages'] as List).single['content'], 'How did the business do this month?');
  });

  test('API key is never written to backups', () async {
    await store.setApiKey('sk-ant-secret');
    expect(jsonEncode(store.toJson()), isNot(contains('sk-ant-secret')));
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
