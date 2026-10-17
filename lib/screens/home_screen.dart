import 'package:flutter/material.dart';

import '../insights.dart';
import '../models.dart';
import '../shell.dart';
import '../store.dart';
import '../theme.dart';
import '../ui.dart';
import 'equipment_screen.dart';
import 'expense_screens.dart' show ShareBar;
import 'item_screens.dart';
import 'purchase_screens.dart';
import 'receipt_screens.dart';
import 'settings_screen.dart';

/// The store's day at a glance: issue supplies, what is running low, where supplies went.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store, required this.shell});
  final WarehouseStore store;
  final Shell shell;

  static String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 18 ? 'Good afternoon' : 'Good evening');
  }

  @override
  Widget build(BuildContext context) {
    final s = store;
    final t = Theme.of(context);
    final w = MediaQuery.sizeOf(context).width;
    final wide = w >= 900;
    final (from, to) = Period.thisMonth.range();

    final all = s.stockList;
    final low = all.where((x) => x.status == StockStatus.low).length;
    final out = all.where((x) => x.status == StockStatus.out).length;
    final monthReceipts = [for (final r in s.receipts) if ((r.date ?? '').compareTo(from) >= 0 && (r.date ?? '').compareTo(to) <= 0) r];
    final spend = departmentSpend(s, from, to);
    final spendTotal = spend.values.fold<num>(0, (a, b) => a + b);
    final insights = [for (final x in buildInsights(s)) if (x.target != InsightTarget.money) x];

    final now = DateTime.now();
    final months = [for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i)];
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final used = [for (final m in months) s.profit(isoDate(m), isoDate(DateTime(m.year, m.month + 1, 0))).suppliesUsed];

    final reorder = all.where((x) => x.status != StockStatus.inStock).toList()
      ..sort((a, b) => _fill(a).compareTo(_fill(b)));
    final recent = s.receipts.reversed.take(5).toList();

    final reorderCard = _Panel(
      title: 'Reorder now',
      action: reorder.isEmpty ? null : ('See all', () => shell.go('Stock', 1)),
      child: reorder.isEmpty
          ? const _Empty(Icons.check_circle_outline, 'Everything is above its minimum level.')
          : Column(children: [for (final x in reorder.take(6)) _StockBar(store: s, x: x)]),
    );
    final recentCard = _Panel(
      title: 'Latest issues',
      action: ('See all', () => shell.go('Issue')),
      child: recent.isEmpty
          ? const _Empty(Icons.outbox_outlined, 'No supplies issued yet.')
          : Column(children: [
              for (final r in recent)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => openReceipt(context, s, r),
                  leading: CircleAvatar(
                    backgroundColor: t.colorScheme.secondaryContainer,
                    child: Text('${r.no}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.colorScheme.onSecondaryContainer)),
                  ),
                  title: NameText(r.department ?? 'No department', style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${fmtDate(r.date)} · ${r.lines.length} ${r.lines.length == 1 ? 'item' : 'items'}'),
                  trailing: const Icon(Icons.chevron_right),
                ),
            ]),
    );

    return Scaffold(
      body: SafeArea(
        child: PageBody(children: [
          const SizedBox(height: 8),
          _Hero(
            greeting: _greeting,
            name: s.companyName.isEmpty ? 'قسم التجهيز' : s.companyName,
            onIssue: () => openReceipt(context, s, null),
            onPurchase: () => openPurchase(context, s, null),
            trailing: w < 700
                ? [
                    _HeroIcon(Icons.medical_services_outlined, 'Equipment', () => _push(context, EquipmentScreen(store: s))),
                    _HeroIcon(Icons.settings_outlined, 'Settings & backup', () => _push(context, SettingsScreen(store: s))),
                  ]
                : const [],
          ),
          const SizedBox(height: 16),
          TileGrid(children: [
            MetricTile(
                label: 'Items in stock',
                value: '${all.length - low - out}',
                icon: Icons.inventory_2_outlined,
                hint: 'of ${all.length} active items',
                onTap: () => shell.go('Stock')),
            MetricTile(
                label: 'Running low',
                value: '$low',
                icon: Icons.trending_down,
                color: low > 0 ? AppColors.warn : null,
                hint: 'At or under minimum',
                onTap: () => shell.go('Stock', 1)),
            MetricTile(
                label: 'Out of stock',
                value: '$out',
                icon: Icons.remove_shopping_cart_outlined,
                color: out > 0 ? AppColors.bad : null,
                hint: 'Nothing left',
                onTap: () => shell.go('Stock', 1)),
            MetricTile(
                label: 'Issued',
                value: '${monthReceipts.length}',
                icon: Icons.outbox_outlined,
                hint: spendTotal > 0 ? 'This month · ${fmtMoneyShort(spendTotal)}' : 'Receipts this month',
                onTap: () => shell.go('Issue')),
          ]),
          const SizedBox(height: 16),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: reorderCard),
              const SizedBox(width: 16),
              Expanded(child: recentCard),
            ])
          else ...[
            reorderCard,
            const SizedBox(height: 16),
            recentCard,
          ],
          const SizedBox(height: 16),
          _Panel(
            title: 'Where supplies went this month',
            child: spend.isEmpty
                ? const _Empty(Icons.pie_chart_outline, 'No issues with a known cost this month.')
                : Column(children: [
                    for (final e in (spend.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(6))
                      ShareBar(label: e.key, value: e.value, total: spendTotal, color: t.colorScheme.primary),
                  ]),
          ),
          if (insights.isNotEmpty) ...[
            SectionTitle('Needs attention', trailing: Text('${insights.length}', style: t.textTheme.labelLarge)),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                for (final (i, x) in insights.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  InsightTile(x, onTap: x.target == null ? null : () => shell.goInsight(x.target!)),
                ],
              ]),
            ),
          ],
          const SectionTitle('Supplies used, last 6 months'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: BarChart(
                labels: [for (final m in months) names[m.month - 1]],
                series: [(name: 'Cost of supplies issued', color: t.colorScheme.primary, values: used)],
              ),
            ),
          ),
          if (s.invoices.isNotEmpty) ...[
            const SectionTitle('Sales'),
            TileGrid(wideColumns: 2, children: [
              MetricTile(
                  label: 'Clients owe you',
                  value: fmtMoneyShort(s.owedToUs),
                  icon: Icons.hourglass_bottom,
                  onTap: () => shell.go('Money', 1)),
              MetricTile(
                  label: 'Sold this month',
                  value: fmtMoneyShort(s.profit(from, to).sales),
                  icon: Icons.trending_up,
                  onTap: () => shell.go('Money', 1)),
            ]),
          ],
        ]),
      ),
    );
  }

  /// How full an item is relative to its minimum (0 = empty), for sorting the reorder list.
  static double _fill(StockInfo x) => x.item.minLevel <= 0 ? (x.qty <= 0 ? -1 : 1) : x.qty / x.item.minLevel;

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ListenableBuilder(listenable: store, builder: (_, _) => page)));
}

/// Cost of supplies issued to each department between two dates (FIFO cost).
Map<String, num> departmentSpend(WarehouseStore s, String from, String to) {
  final out = <String, num>{};
  for (final r in s.receipts) {
    final d = r.date;
    if (d == null || d.compareTo(from) < 0 || d.compareTo(to) > 0) continue;
    var cost = 0 as num;
    for (final (i, _) in r.lines.indexed) {
      cost += s.ledger.lineCost['rcp:${r.no}:$i'] ?? 0;
    }
    if (cost > 0) out[r.department ?? 'No department'] = (out[r.department ?? 'No department'] ?? 0) + cost;
  }
  return out;
}

class _Hero extends StatelessWidget {
  const _Hero({required this.greeting, required this.name, required this.onIssue, required this.onPurchase, this.trailing = const []});
  final String greeting, name;
  final VoidCallback onIssue, onPurchase;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final phone = isPhone(context);
    final issue = FilledButton.icon(
      style: FilledButton.styleFrom(
          backgroundColor: Colors.white, foregroundColor: AppColors.brand, minimumSize: const Size(0, 52), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      onPressed: onIssue,
      icon: const Icon(Icons.outbox_outlined),
      label: const Text('Issue to department'),
    );
    final purchase = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70), minimumSize: const Size(0, 52), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      onPressed: onPurchase,
      icon: const Icon(Icons.add_shopping_cart),
      label: const Text('Record purchase'),
    );
    return Container(
      padding: EdgeInsets.all(phone ? 20 : 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F766E), Color(0xFF115E59), Color(0xFF134E4A)],
        ),
        boxShadow: const [BoxShadow(color: Color(0x330F766E), blurRadius: 24, offset: Offset(0, 10))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fmtDate(todayIso()), style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(greeting, style: t.textTheme.headlineMedium!.copyWith(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: -.5)),
              const SizedBox(height: 2),
              NameText(name, style: t.textTheme.titleMedium!.copyWith(color: Colors.white.withValues(alpha: .9))),
            ]),
          ),
          ...trailing,
        ]),
        SizedBox(height: phone ? 20 : 26),
        if (phone)
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [issue, const SizedBox(height: 10), purchase])
        else
          Wrap(spacing: 12, runSpacing: 12, children: [issue, purchase]),
      ]),
    );
  }
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon(this.icon, this.tooltip, this.onTap);
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
        style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: .14)),
      );
}

/// A titled card with an optional "See all" link.
class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.action});
  final String title;
  final Widget child;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title, style: t.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w800))),
            if (action != null) TextButton(onPressed: action!.$2, child: Text(action!.$1)),
          ]),
          const SizedBox(height: 6),
          Padding(padding: const EdgeInsets.only(right: 8), child: child),
        ]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(children: [
          Icon(icon, color: AppColors.good),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
        ]),
      );
}

/// Item name with a bar showing stock against its minimum level.
class _StockBar extends StatelessWidget {
  const _StockBar({required this.store, required this.x});
  final WarehouseStore store;
  final StockInfo x;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final color = x.status == StockStatus.out ? AppColors.bad : AppColors.warn;
    final min = x.item.minLevel;
    final f = min <= 0 ? 0.0 : (x.qty / (min * 2)).clamp(0, 1).toDouble();
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ItemDetailScreen(store: store, itemId: x.item.id))),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: NameText(x.item.name, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text('${fmtQty(x.qty)} ', style: TextStyle(fontWeight: FontWeight.w800, color: color)),
            NameText(x.item.unit, style: t.textTheme.bodySmall),
            Text('  · min ${fmtQty(min)}', style: t.textTheme.bodySmall),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: f, minHeight: 6, color: color, backgroundColor: t.colorScheme.surfaceContainerHighest),
          ),
        ]),
      ),
    );
  }
}

class InsightTile extends StatelessWidget {
  const InsightTile(this.x, {super.key, this.onTap});
  final Insight x;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (x.level) {
      InsightLevel.urgent => (Icons.error, AppColors.bad),
      InsightLevel.warning => (Icons.warning_amber_rounded, AppColors.warn),
      InsightLevel.good => (Icons.trending_up, AppColors.good),
      InsightLevel.tip => (Icons.lightbulb_outline, AppColors.info),
    };
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(backgroundColor: color.withValues(alpha: .12), child: Icon(icon, color: color, size: 22)),
      title: Text(x.title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(x.detail),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
    );
  }
}
