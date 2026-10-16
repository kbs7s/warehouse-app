import 'models.dart';

/// A batch of stock bought at one price ("asset layer"). Sales and internal use take
/// from the oldest layer first (FIFO), so the cost of what left the store is exact.
class CostLayer {
  CostLayer({required this.itemId, required this.date, required this.source, required this.qtyIn, required this.unitCost, this.estimatedCost = false})
      : qtyLeft = qtyIn;
  final String itemId;
  final String? date;
  final String source; // "Opening stock", "Purchase #3 · supplier"
  final num qtyIn;
  final num unitCost;
  final bool estimatedCost; // opening stock with no known price
  num qtyLeft;

  num get valueLeft => qtyLeft * unitCost;
}

/// Money summary for a period, in plain terms.
class ProfitReport {
  ProfitReport({
    required this.from,
    required this.to,
    required this.sales,
    required this.costOfSales,
    required this.suppliesUsed,
    required this.expenses,
    required this.expensesByCategory,
    required this.received,
  });
  final String from, to;
  final num sales; // invoiced to clients (after discounts)
  final num costOfSales; // what the sold stock cost us (FIFO)
  final num suppliesUsed; // cost of stock given to departments / used internally
  final num expenses; // rent, salaries, ...
  final Map<String, num> expensesByCategory;
  final num received; // cash actually collected from clients in the period

  num get grossProfit => sales - costOfSales;
  num get profit => grossProfit - suppliesUsed - expenses;
  double get margin => sales == 0 ? 0 : profit / sales;
}

typedef _Event = ({String date, int order, String key, String itemId, num qty, num? unitCost, String source, bool inbound});

/// Replays every purchase, sale and issue in date order and works out stock layers and costs.
class Ledger {
  Ledger._();

  /// Remaining layers per item (oldest first).
  final Map<String, List<CostLayer>> layers = {};

  /// Cost of each outgoing line, keyed `inv:NO:LINE` (invoices) or `rcp:NO:LINE` (issues).
  final Map<String, num> lineCost = {};

  /// Quantity that left the store with no stock to cover it (stock went below zero).
  final Map<String, num> shortfall = {};

  num get stockValue => layers.values.expand((l) => l).fold<num>(0, (s, l) => s + l.valueLeft);
  num itemValue(String itemId) => (layers[itemId] ?? const []).fold<num>(0, (s, l) => s + l.valueLeft);

  /// What selling [qty] more of an item now would cost, taking the oldest layers first.
  num estimateCost(String itemId, num qty) {
    var need = qty;
    num cost = 0;
    final q = layers[itemId] ?? const <CostLayer>[];
    for (final l in q) {
      if (need <= 0) break;
      final take = need < l.qtyLeft ? need : l.qtyLeft;
      cost += take * l.unitCost;
      need -= take;
    }
    if (need > 0 && q.isNotEmpty) cost += need * q.last.unitCost;
    return cost;
  }

  /// Unit cost of the newest layer still in stock, if any.
  num? latestUnitCost(String itemId) {
    final q = layers[itemId];
    return q == null || q.isEmpty ? null : q.last.unitCost;
  }

  static Ledger build({
    required List<Item> items,
    required List<Purchase> purchases,
    required List<Receipt> receipts,
    required List<Invoice> invoices,
  }) {
    final led = Ledger._();
    final events = <_Event>[];
    // Undated records (imported from Excel) count as the oldest.
    String d(String? date) => date ?? '';

    final firstPrice = <String, num>{};
    final sortedPurchases = [...purchases]..sort((a, b) {
        final c = d(a.date).compareTo(d(b.date));
        return c != 0 ? c : a.no.compareTo(b.no);
      });
    for (final p in sortedPurchases) {
      for (final (i, l) in p.lines.indexed) {
        if (l.qty <= 0) continue;
        final unit = l.total > 0 ? l.total / l.qty : (l.unitPrice ?? 0);
        if (unit > 0) firstPrice.putIfAbsent(l.itemId, () => unit);
        events.add((
          date: d(p.date), order: 1, key: 'pur:${p.no}:$i', itemId: l.itemId, qty: l.qty, unitCost: unit,
          source: 'Purchase #${p.no}${p.supplier == null ? '' : ' · ${p.supplier}'}', inbound: true,
        ));
      }
    }
    for (final r in receipts) {
      for (final (i, l) in r.lines.indexed) {
        events.add((date: d(r.date), order: 2, key: 'rcp:${r.no}:$i', itemId: l.itemId, qty: l.qty, unitCost: null,
            source: 'Issue #${r.no}', inbound: false));
      }
    }
    for (final inv in invoices) {
      for (final (i, l) in inv.lines.indexed) {
        if (l.itemId == null) continue;
        events.add((date: d(inv.date), order: 2, key: 'inv:${inv.no}:$i', itemId: l.itemId!, qty: l.qty, unitCost: null,
            source: 'Invoice #${inv.no}', inbound: false));
      }
    }
    // Same day: stock comes in before it goes out.
    events.sort((a, b) {
      final c = a.date.compareTo(b.date);
      if (c != 0) return c;
      return a.order.compareTo(b.order);
    });

    for (final it in items) {
      final q = led.layers[it.id] = [];
      if (it.openingQty > 0) {
        final cost = it.openingUnitCost ?? firstPrice[it.id];
        q.add(CostLayer(
            itemId: it.id, date: null, source: 'Opening stock', qtyIn: it.openingQty,
            unitCost: cost ?? 0, estimatedCost: it.openingUnitCost == null));
      }
    }

    for (final e in events) {
      final q = led.layers.putIfAbsent(e.itemId, () => []);
      if (e.inbound) {
        q.add(CostLayer(itemId: e.itemId, date: e.date.isEmpty ? null : e.date, source: e.source, qtyIn: e.qty, unitCost: e.unitCost!));
        continue;
      }
      var need = e.qty;
      num cost = 0;
      for (final layer in q) {
        if (need <= 0) break;
        if (layer.qtyLeft <= 0) continue;
        final take = need < layer.qtyLeft ? need : layer.qtyLeft;
        layer.qtyLeft -= take;
        cost += take * layer.unitCost;
        need -= take;
      }
      if (need > 0) {
        // Not enough recorded stock: value the missing units at the latest known price.
        led.shortfall[e.itemId] = (led.shortfall[e.itemId] ?? 0) + need;
        final last = q.isNotEmpty ? q.last.unitCost : (firstPrice[e.itemId] ?? 0);
        cost += need * last;
      }
      led.lineCost[e.key] = cost;
    }
    for (final q in led.layers.values) {
      q.removeWhere((l) => l.qtyLeft <= 0);
    }
    return led;
  }

  /// Profit between two dates (inclusive, yyyy-MM-dd).
  ProfitReport report({
    required String from,
    required String to,
    required List<Invoice> invoices,
    required List<Receipt> receipts,
    required List<Expense> expenses,
  }) {
    bool inRange(String? d) => d != null && d.compareTo(from) >= 0 && d.compareTo(to) <= 0;
    num sales = 0, cos = 0, used = 0, exp = 0, received = 0;
    final byCat = <String, num>{};
    for (final inv in invoices) {
      for (final p in inv.payments) {
        if (inRange(p.date)) received += p.amount;
      }
      if (!inRange(inv.date)) continue;
      sales += inv.total;
      for (final (i, _) in inv.lines.indexed) {
        cos += lineCost['inv:${inv.no}:$i'] ?? 0;
      }
    }
    for (final r in receipts) {
      if (!inRange(r.date)) continue;
      for (final (i, _) in r.lines.indexed) {
        used += lineCost['rcp:${r.no}:$i'] ?? 0;
      }
    }
    for (final e in expenses) {
      if (!inRange(e.date)) continue;
      exp += e.amount;
      byCat[e.category] = (byCat[e.category] ?? 0) + e.amount;
    }
    return ProfitReport(
        from: from, to: to, sales: sales, costOfSales: cos, suppliesUsed: used, expenses: exp,
        expensesByCategory: byCat, received: received);
  }
}
