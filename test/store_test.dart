import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_app/models.dart';
import 'package:warehouse_app/store.dart';

WarehouseStore seeded() {
  final s = WarehouseStore(null);
  s.applyJson(jsonDecode(File('seed/app_seed.json').readAsStringSync()) as Map<String, dynamic>, save: false);
  return s;
}

void main() {
  test('stock from the Excel import matches the Excel ALL sheet', () {
    final s = seeded();
    expect(s.items.length, 141);
    // Values copied from the ALL sheet "Result Qty" column.
    expect(s.stock('P001').qty, 510);
    expect(s.stock('P003').qty, 0);
    expect(s.stock('P009').qty, -480);
    expect(s.stock('P051').qty, 6);
    expect(s.stock('P079').qty, 96);
    expect(s.stock('P113').qty, 122);
    expect(s.stock('P001').status, StockStatus.inStock);
    expect(s.stock('P079').status, StockStatus.low); // 96 <= min 250
    expect(s.stock('P003').status, StockStatus.out);
  });

  test('issuing and deleting a receipt moves stock', () {
    final s = seeded();
    final no = s.nextReceiptNo;
    expect(no, 21);
    s.saveReceipt(Receipt(no: no, date: '2026-10-01', department: 'NICU', lines: [ReceiptLine(itemId: 'P001', qty: 10)]));
    expect(s.stock('P001').qty, 500);
    s.saveReceipt(Receipt(no: no, date: '2026-10-01', department: 'NICU', lines: [ReceiptLine(itemId: 'P001', qty: 4)]));
    expect(s.stock('P001').qty, 506, reason: 'editing replaces, not adds');
    s.deleteReceipt(no);
    expect(s.stock('P001').qty, 510);
  });

  test('purchases add stock and new suppliers are remembered', () {
    final s = seeded();
    s.savePurchase(Purchase(no: s.nextPurchaseNo, supplier: 'مورد جديد', lines: [
      PurchaseLine(itemId: 'P003', qty: 30, unitPrice: 7500),
    ]));
    expect(s.stock('P003').qty, 30);
    expect(s.purchases.last.total, 225000);
    expect(s.suppliers, contains('مورد جديد'));
  });

  test('new item codes continue the Excel numbering', () {
    final s = seeded();
    expect(s.nextItemId, 'P277');
    s.saveItem(Item(id: s.nextItemId, name: 'شاش معقم', unit: 'باكيت', openingQty: 5, minLevel: 2));
    expect(s.stock('P277').qty, 5);
    expect(s.nameTaken(' شاش معقم '), isTrue);
  });

  test('backup round trip keeps everything', () {
    final s = seeded();
    s.saveReceipt(Receipt(no: 99, date: '2026-10-01', department: 'Hotel', lines: [ReceiptLine(itemId: 'P185', qty: 5)]));
    final copy = WarehouseStore(null)..applyJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>, save: false);
    expect(jsonEncode(copy.toJson()..remove('savedAt')), jsonEncode(s.toJson()..remove('savedAt')));
    expect(copy.stock('P185').qty, s.stock('P185').qty);
    expect(() => copy.applyJson({'hello': 1}), throwsFormatException);
  });

  test('a new device starts empty and can start fresh or erase', () async {
    final s = WarehouseStore(null);
    await s.load();
    expect(s.started, isFalse);
    s.startEmpty();
    expect(s.started, isTrue);
    expect(s.items, isEmpty);
    s.saveItem(Item(id: s.nextItemId, name: 'test', unit: 'قطعة'));
    expect(s.items.single.id, 'P002');
    await s.eraseAll();
    expect(s.started, isFalse);
    expect(s.items, isEmpty);
  });
}
