import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_app/main.dart';
import 'package:warehouse_app/pdf.dart';
import 'package:warehouse_app/store.dart';

void main() {
  late WarehouseStore store;
  setUp(() {
    store = WarehouseStore(null)
      ..applyJson(jsonDecode(File('seed/app_seed.json').readAsStringSync()) as Map<String, dynamic>,
          save: false);
  });

  testWidgets('stock screen lists items and filters low stock', (t) async {
    t.view.physicalSize = const Size(2360, 1640);
    t.view.devicePixelRatio = 2;
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeShell(store: store)));
    expect(find.text('اسفنجة تعقيم'), findsOneWidget);
    await t.tap(find.textContaining('Low'));
    await t.pump();
    expect(find.text('شرشف لاستيك مريض'), findsOneWidget);
    expect(find.text('اسفنجة تعقيم'), findsNothing);
  });

  testWidgets('new receipt reduces stock', (t) async {
    t.view.physicalSize = const Size(2360, 1640);
    t.view.devicePixelRatio = 2;
    await t.pumpWidget(MaterialApp(theme: buildTheme(), home: HomeShell(store: store)));
    await t.tap(find.text('Issue'));
    await t.pumpAndSettle();
    await t.tap(find.text('New receipt'));
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

  test('receipt PDF builds with Arabic names', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes = await buildReceiptPdf(store, store.receipts.firstWhere((r) => r.no == 20));
    expect(bytes.length, greaterThan(10000));
    File('build/receipt-20.pdf')
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
  });
}
