import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_app/models.dart';
import 'package:warehouse_app/store.dart';

void main() {
  WarehouseStore small() => WarehouseStore(null)
    ..startEmpty()
    ..saveItem(Item(id: 'A', name: 'Gloves', unit: 'box', openingQty: 10, openingUnitCost: 100))
    ..savePurchase(Purchase(no: 1, date: '2026-10-02', supplier: 'S', lines: [PurchaseLine(itemId: 'A', qty: 10, unitPrice: 150)]));

  test('sales use the oldest stock first (FIFO)', () {
    final s = small();
    s.saveInvoice(Invoice(no: 1, date: '2026-10-05', lines: [InvoiceLine(itemId: 'A', qty: 15, unitPrice: 200)]));
    expect(s.invoiceLineCost(1, 0), 10 * 100 + 5 * 150);
    expect(s.stock('A').qty, 5);
    final layers = s.ledger.layers['A']!;
    expect(layers.length, 1);
    expect(layers.single.qtyLeft, 5);
    expect(layers.single.unitCost, 150);
    expect(s.ledger.stockValue, 750);
  });

  test('profit = sales - cost of sales - supplies used - expenses', () {
    final s = small();
    s.saveInvoice(Invoice(no: 1, date: '2026-10-05', lines: [
      InvoiceLine(itemId: 'A', qty: 15, unitPrice: 200),
      InvoiceLine(description: 'Delivery', qty: 1, unitPrice: 1000),
    ], discount: 1000, payments: [InvoicePayment(date: '2026-10-06', amount: 1000)]));
    s.saveReceipt(Receipt(no: 1, date: '2026-10-06', department: 'Ward', lines: [ReceiptLine(itemId: 'A', qty: 3)]));
    s.saveExpense(Expense(id: 'e1', date: '2026-10-07', category: 'Rent', amount: 500));
    final r = s.profit('2026-10-01', '2026-10-31');
    expect(r.sales, 3000); // 3000 + 1000 delivery - 1000 discount
    expect(r.costOfSales, 1750);
    expect(r.suppliesUsed, 3 * 150);
    expect(r.expenses, 500);
    expect(r.profit, 3000 - 1750 - 450 - 500);
    expect(r.received, 1000);
    expect(s.owedToUs, 2000);
    expect(s.profit('2026-11-01', '2026-11-30').sales, 0);
  });

  test('selling more than in stock is valued at the latest price and flagged', () {
    final s = small();
    s.saveInvoice(Invoice(no: 1, date: '2026-10-05', lines: [InvoiceLine(itemId: 'A', qty: 23, unitPrice: 200)]));
    expect(s.ledger.shortfall['A'], 3);
    expect(s.invoiceLineCost(1, 0), 1000 + 1500 + 3 * 150);
    expect(s.stock('A').qty, -3);
  });

  test('invoice status follows payments and due date', () {
    final inv = Invoice(no: 1, date: '2026-10-01', dueDate: '2026-10-10', lines: [InvoiceLine(description: 'x', qty: 1, unitPrice: 100)]);
    expect(inv.status('2026-10-05'), InvoiceStatus.unpaid);
    expect(inv.status('2026-10-11'), InvoiceStatus.overdue);
    inv.payments.add(InvoicePayment(date: '2026-10-11', amount: 40));
    expect(inv.status('2026-10-05'), InvoiceStatus.partlyPaid);
    inv.payments.add(InvoicePayment(date: '2026-10-12', amount: 60));
    expect(inv.status('2026-10-20'), InvoiceStatus.paid);
  });

  test('Excel data: layers match stock and v1 backups still load', () {
    final s = WarehouseStore(null)
      ..applyJson(jsonDecode(File('seed/app_seed.json').readAsStringSync()) as Map<String, dynamic>, save: false);
    for (final st in s.stockList) {
      final left = s.ledger.layers[st.item.id]!.fold<num>(0, (t, l) => t + l.qtyLeft);
      expect(left, st.qty > 0 ? st.qty : 0, reason: st.item.id);
    }
    expect(s.ledger.shortfall.keys.toSet(), containsAll(['P009', 'P063', 'P065']));
    expect(s.ledger.stockValue, greaterThan(0));
    final round = WarehouseStore(null)..applyJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>, save: false);
    expect(round.ledger.stockValue, s.ledger.stockValue);
  });
}
