import 'package:flutter/material.dart';

import '../insights.dart';
import '../shell.dart';
import '../store.dart';
import '../theme.dart';
import '../ui.dart';
import 'equipment_screen.dart';
import 'expense_screens.dart';
import 'invoice_screens.dart';
import 'profit_screen.dart';
import 'purchase_screens.dart';
import 'receipt_screens.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, required this.shell});
  final WarehouseStore store;
  final Shell shell;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Period _period = Period.thisMonth;

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 18 ? 'Good afternoon' : 'Good evening');
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final (from, to) = _period.range();
    final r = s.profit(from, to);
    final insights = buildInsights(s);
    final t = Theme.of(context);
    final phone = isPhone(context);

    final now = DateTime.now();
    final months = [for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i)];
    final monthly = [for (final m in months) s.profit(isoDate(m), isoDate(DateTime(m.year, m.month + 1, 0)))];
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_greeting, style: t.textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w800)),
          Text(s.companyName.isEmpty ? "Here's how your business is doing" : s.companyName,
              style: t.textTheme.bodyMedium!.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ]),
        actions: [
          if (MediaQuery.sizeOf(context).width < 700) ...[
            IconButton(
                tooltip: 'Equipment',
                icon: const Icon(Icons.medical_services_outlined),
                onPressed: () => _push(context, EquipmentScreen(store: s))),
            IconButton(
                tooltip: 'Settings & backup',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => _push(context, SettingsScreen(store: s))),
          ],
          const SizedBox(width: 8),
        ],
      ),
      body: PageBody(children: [
        PeriodChips(value: _period, onChanged: (p) => setState(() => _period = p)),
        const SizedBox(height: 16),
        TileGrid(children: [
          MetricTile(
              label: 'Sales', value: fmtMoneyShort(r.sales), icon: Icons.trending_up, hint: 'Invoiced to clients',
              onTap: () => widget.shell.go('Sales')),
          MetricTile(
              label: 'Profit',
              value: fmtMoneyShort(r.profit),
              icon: Icons.savings_outlined,
              color: r.profit >= 0 ? AppColors.good : AppColors.bad,
              hint: r.sales == 0 || r.profit < 0 ? 'After all costs' : '${(r.margin * 100).toStringAsFixed(0)}% of sales kept',
              onTap: () => widget.shell.go('Money')),
          MetricTile(
              label: 'Clients owe you',
              value: fmtMoneyShort(s.owedToUs),
              icon: Icons.hourglass_bottom,
              color: s.overdue(todayIso()).isEmpty ? null : AppColors.warn,
              hint: '${s.overdue(todayIso()).length} overdue',
              onTap: () => widget.shell.go('Sales')),
          MetricTile(
              label: 'Stock value',
              value: fmtMoneyShort(s.ledger.stockValue),
              icon: Icons.layers_outlined,
              hint: 'What your stock cost (oldest first)',
              onTap: () => widget.shell.go('Stock')),
        ]),
        const SizedBox(height: 16),
        ProfitStory(r: r),
        const SectionTitle('Quick actions'),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _Action(Icons.receipt_long, 'New invoice', () => openInvoice(context, s, null)),
          _Action(Icons.add_shopping_cart, 'Record purchase', () => openPurchase(context, s, null)),
          _Action(Icons.payments_outlined, 'Add expense', () => openExpense(context, s, null)),
          _Action(Icons.outbox_outlined, 'Issue to department', () => openReceipt(context, s, null)),
          _Action(Icons.auto_awesome, 'Ask the assistant', () => widget.shell.go('Assistant'), filled: true),
        ]),
        SectionTitle('Needs attention', trailing: Text('${insights.length}', style: t.textTheme.labelLarge)),
        if (insights.isEmpty)
          const Card(child: ListTile(leading: Icon(Icons.check_circle, color: AppColors.good), title: Text('All good. Nothing needs you right now.'))),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final (i, x) in insights.indexed) ...[
              if (i > 0) const Divider(height: 1),
              InsightTile(x, onTap: x.target == null ? null : () => widget.shell.goInsight(x.target!)),
            ],
          ]),
        ),
        const SectionTitle('Last 6 months'),
        Card(
          child: Padding(
            padding: EdgeInsets.all(phone ? 14 : 20),
            child: BarChart(
              labels: [for (final m in months) names[m.month - 1]],
              series: [
                (name: 'Sales', color: t.colorScheme.primary.withValues(alpha: .35), values: [for (final m in monthly) m.sales]),
                (name: 'Profit', color: AppColors.good, values: [for (final m in monthly) m.profit]),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => ListenableBuilder(listenable: widget.store, builder: (_, _) => page)));
}

class _Action extends StatelessWidget {
  const _Action(this.icon, this.label, this.onTap, {this.filled = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) => filled
      ? FilledButton.icon(onPressed: onTap, icon: Icon(icon, size: 20), label: Text(label))
      : OutlinedButton.icon(onPressed: onTap, icon: Icon(icon, size: 20), label: Text(label));
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

