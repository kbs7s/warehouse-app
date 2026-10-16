import 'package:flutter/material.dart';

import '../ledger.dart';
import '../shell.dart';
import '../store.dart';
import '../theme.dart';
import '../ui.dart';
import 'expense_screens.dart';

/// Profit and loss in plain words, for someone with no bookkeeping background.
class ProfitScreen extends StatefulWidget {
  const ProfitScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  State<ProfitScreen> createState() => _ProfitScreenState();
}

class _ProfitScreenState extends State<ProfitScreen> {
  Period _period = Period.thisMonth;

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final t = Theme.of(context);
    final (from, to) = _period.range();
    final r = s.profit(from, to);
    final best = _bestSellers(s, from, to);
    final cats = r.expensesByCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final worth = s.ledger.stockValue + s.owedToUs - s.weOwe;

    final now = DateTime.now();
    final months = [for (var i = 11; i >= 0; i--) DateTime(now.year, now.month - i)];
    final monthly = [for (final m in months) s.profit(isoDate(m), isoDate(DateTime(m.year, m.month + 1, 0)))];
    const names = ['J', 'F', 'M', 'A', 'M', 'J', 'J', 'A', 'S', 'O', 'N', 'D'];

    return Scaffold(
      appBar: AppBar(title: const Text('Profit'), bottom: SubNav.bar(context)),
      body: PageBody(children: [
        PeriodChips(value: _period, onChanged: (p) => setState(() => _period = p)),
        const SizedBox(height: 14),
        TileGrid(children: [
          MetricTile(label: 'Sales', value: fmtMoneyShort(r.sales), icon: Icons.trending_up),
          MetricTile(label: 'Gross profit', value: fmtMoneyShort(r.grossProfit), icon: Icons.inventory_2_outlined, hint: 'Sales minus what the goods cost'),
          MetricTile(
              label: 'Net profit',
              value: fmtMoneyShort(r.profit),
              icon: Icons.savings_outlined,
              color: r.profit >= 0 ? AppColors.good : AppColors.bad,
              hint: 'After every cost'),
          MetricTile(label: 'Cash collected', value: fmtMoneyShort(r.received), icon: Icons.payments_outlined, hint: 'Money that actually came in'),
        ]),
        const SizedBox(height: 14),
        ProfitStory(r: r),
        const SectionTitle('Last 12 months'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: BarChart(
              labels: [for (final m in months) names[m.month - 1]],
              series: [
                (name: 'Sales', color: t.colorScheme.primary.withValues(alpha: .35), values: [for (final m in monthly) m.sales]),
                (name: 'Net profit', color: AppColors.good, values: [for (final m in monthly) m.profit]),
              ],
            ),
          ),
        ),
        const SectionTitle('What made you money'),
        if (best.isEmpty)
          const Card(child: ListTile(title: Text('No sales in this period.')))
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final (i, b) in best.take(10).indexed) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  title: NameText(b.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Sold ${fmtMoney(b.sales)} · cost ${fmtMoney(b.cost)}'),
                  trailing: Text(fmtMoney(b.sales - b.cost),
                      style: TextStyle(fontWeight: FontWeight.w700, color: b.sales >= b.cost ? AppColors.good : AppColors.bad)),
                ),
              ],
            ]),
          ),
        const SectionTitle('Where running costs went'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: cats.isEmpty
                ? const Text('No expenses recorded in this period.')
                : Column(children: [for (final c in cats) ShareBar(label: c.key, value: c.value, total: r.expenses)]),
          ),
        ),
        const SectionTitle('What the business is worth right now'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(children: [
              _row(context, 'Stock on the shelves (at cost)', s.ledger.stockValue),
              _row(context, 'Money clients still owe you', s.owedToUs),
              _row(context, 'Money you still owe suppliers', -s.weOwe),
              const Divider(height: 22),
              _row(context, 'Net', worth, bold: true),
              const SizedBox(height: 6),
              Text('Cash in hand or in the bank is not tracked here.', style: t.textTheme.bodySmall),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        const _Glossary(),
      ]),
    );
  }

  Widget _row(BuildContext context, String label, num v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w800 : null))),
          Text(fmtMoney(v), style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: bold ? (v >= 0 ? AppColors.good : AppColors.bad) : null)),
        ]),
      );
}

typedef _Best = ({String name, num sales, num cost});

List<_Best> _bestSellers(WarehouseStore s, String from, String to) {
  final m = <String, _Best>{};
  for (final inv in s.invoices) {
    if (inv.date.compareTo(from) < 0 || inv.date.compareTo(to) > 0) continue;
    // Spread the invoice discount over its lines so totals match sales.
    final share = inv.subtotal == 0 ? 0 : inv.discount / inv.subtotal;
    for (final (i, l) in inv.lines.indexed) {
      final key = l.itemId ?? 'svc:${l.description ?? 'Service'}';
      final name = l.itemId == null ? (l.description ?? 'Service') : (s.item(l.itemId!)?.name ?? l.itemId!);
      final prev = m[key] ?? (name: name, sales: 0, cost: 0);
      m[key] = (name: name, sales: prev.sales + l.total * (1 - share), cost: prev.cost + s.invoiceLineCost(inv.no, i));
    }
  }
  return m.values.toList()..sort((a, b) => (b.sales - b.cost).compareTo(a.sales - a.cost));
}

/// "You sold X. It cost Y. ... You kept Z." The profit report in one card.
class ProfitStory extends StatelessWidget {
  const ProfitStory({super.key, required this.r});
  final ProfitReport r;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final good = r.profit >= 0;
    final lines = <(String, num)>[
      ('You sold', r.sales),
      ('The goods you sold cost you', -r.costOfSales),
      if (r.suppliesUsed != 0) ('Supplies used by departments', -r.suppliesUsed),
      ('Running costs (rent, salaries…)', -r.expenses),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Where the money went', style: t.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [Expanded(child: Text(l.$1)), Text(fmtMoney(l.$2))]),
            ),
          const Divider(height: 20),
          Row(children: [
            Expanded(
                child: Text(good ? 'You kept (profit)' : 'You lost', style: t.textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w800))),
            Text(fmtMoney(r.profit),
                style: t.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w800, color: good ? AppColors.good : AppColors.bad)),
          ]),
          if (r.received != r.sales) ...[
            const SizedBox(height: 8),
            Text('Cash actually collected in this period: ${fmtMoney(r.received)}',
                style: t.textTheme.bodySmall!.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ],
        ]),
      ),
    );
  }
}

class _Glossary extends StatelessWidget {
  const _Glossary();

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          leading: const Icon(Icons.help_outline),
          title: const Text('What do these words mean?'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            _Term('Sales', 'The total of the invoices you gave clients, after discounts. It counts when you bill, not when they pay.'),
            _Term('Cost of goods sold', 'What the stock you sold had cost you to buy. The oldest stock is counted as sold first, '
                'so the cost uses the price you actually paid for those units (this is called FIFO).'),
            _Term('Gross profit', 'Sales minus the cost of goods sold. What the selling itself earned.'),
            _Term('Supplies used', 'Stock given to departments for internal use. It earns nothing, so its cost is subtracted.'),
            _Term('Expenses', 'Running costs that are not stock: rent, salaries, electricity, transport.'),
            _Term('Net profit', 'What is left after every cost. This is what the business really earned.'),
            _Term('Cash collected', 'Money clients actually paid in the period. It can be lower than sales when invoices are unpaid.'),
            _Term('Stock layers', 'Each purchase is a separate batch at its own price. When you sell, the oldest batch is used first.'),
          ],
        ),
      );
}

class _Term extends StatelessWidget {
  const _Term(this.term, this.meaning);
  final String term, meaning;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: '$term: ', style: const TextStyle(fontWeight: FontWeight.w700)),
          TextSpan(text: meaning),
        ])),
      );
}
