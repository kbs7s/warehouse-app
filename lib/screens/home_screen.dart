import 'package:flutter/material.dart';

import '../expiry.dart';
import '../insights.dart';
import '../l10n.dart';
import '../models.dart';
import '../month.dart';
import '../shell.dart';
import '../store.dart';
import '../theme.dart';
import '../ui.dart';
import 'equipment_screen.dart';
import 'expiry_screens.dart';
import 'expense_screens.dart' show ShareBar;
import 'item_screens.dart';
import 'purchase_screens.dart';
import 'receipt_screens.dart';
import 'reports_screen.dart' show reorderList;
import 'cloud_screens.dart';
import 'settings_screen.dart';

/// The store's day at a glance: issue supplies, what is running low, where supplies went.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.store, required this.shell});
  final WarehouseStore store;
  final Shell shell;

  static String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? tx('Good morning', 'صباح الخير') : (h < 18 ? tx('Good afternoon', 'مساء الخير') : tx('Good evening', 'مساء الخير'));
  }

  @override
  Widget build(BuildContext context) {
    final s = store;
    final t = Theme.of(context);
    final w = MediaQuery.sizeOf(context).width;
    final wide = w >= 900;
    // "This month" is the open month on the Month page, so it starts again after each month-end close.
    final (from, to) = (s.openMonthStart, '9999-12-31');

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

    final reorder = [for (final (x, _) in reorderList(s)) x];
    final recent = s.receipts.reversed.take(5).toList();

    final reorderCard = _Panel(
      title: tx('Reorder now', 'إعادة الطلب الآن'),
      action: reorder.isEmpty ? null : (tx('See all', 'عرض الكل'), () => shell.go('Stock', 1)),
      child: reorder.isEmpty
          ? _Empty(Icons.check_circle_outline, tx('Everything is above its minimum level.', 'كل المواد فوق الحد الأدنى.'))
          : Column(children: [for (final x in reorder.take(6)) _StockBar(store: s, x: x)]),
    );
    final expiring = s.expiryAlerts;
    final hasDates = s.items.any((i) => i.expiries.isNotEmpty);
    final expiryCard = _Panel(
      title: tx('Expiring soon', 'قريبة الانتهاء'),
      action: (hasDates ? tx('See all', 'عرض الكل') : tx('Add dates', 'إضافة تواريخ'), () => shell.go('Stock', 2)),
      child: expiring.isEmpty
          ? _Empty(
              Icons.event_available,
              hasDates
                  ? tx('Nothing expires within ${s.expiryWarnDays} days.', 'لا شيء ينتهي خلال ${s.expiryWarnDays} يوماً.')
                  : tx('Add expiry dates to items to get a warning before they expire.', 'أضف تواريخ الانتهاء للمواد ليصلك تنبيه قبل انتهائها.'))
          : Column(children: [
              for (final e in expiring.take(5))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ItemDetailScreen(store: s, itemId: e.item.id))),
                  title: NameText(e.item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(batchLine(e.batch, e.item.unit)),
                  trailing: ExpiryChip(e),
                ),
            ]),
    );
    final whereCard = _Panel(
      title: tx('Where supplies went this month', 'أين ذهبت المواد هذا الشهر'),
      child: spend.isEmpty
          ? _Empty(Icons.pie_chart_outline, tx('No issues with a known cost this month.', 'لا توجد صرفيات بكلفة معروفة هذا الشهر.'))
          : Column(children: [
              for (final e in (spend.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(6))
                ShareBar(label: e.key, value: e.value, total: spendTotal, color: t.colorScheme.primary),
            ]),
    );
    final recentCard = _Panel(
      title: tx('Latest issues', 'آخر الصرفيات'),
      action: (tx('See all', 'عرض الكل'), () => shell.go('Issue')),
      child: recent.isEmpty
          ? _Empty(Icons.outbox_outlined, tx('No supplies issued yet.', 'لم يُصرف شيء بعد.'))
          : Column(children: [
              for (final r in recent)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => openReceipt(context, s, r),
                  leading: CircleAvatar(
                    backgroundColor: t.colorScheme.secondaryContainer,
                    child: Text('${r.no}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.colorScheme.onSecondaryContainer)),
                  ),
                  title: NameText(r.department ?? tx('No department', 'بدون قسم'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${fmtDate(r.date)} · ${r.lines.length} ${r.lines.length == 1 ? tx('item', 'مادة') : tx('items', 'مواد')}'),
                  trailing: const Icon(Icons.chevron_right),
                ),
            ]),
    );

    return Scaffold(
      body: SafeArea(
        child: PageBody(children: [
          const SizedBox(height: 8),
          if (s.backupDue && !(s.cloud?.isStaff ?? false)) ...[
            BackupReminder(store: s),
            const SizedBox(height: 12),
          ],
          _Hero(
            greeting: _greeting,
            name: s.companyName.isEmpty ? 'قسم التجهيز' : s.companyName,
            onIssue: () => openReceipt(context, s, null),
            onPurchase: () => openPurchase(context, s, null),
            trailing: [
              SyncBadge(store: s, onTap: () => _push(context, SettingsScreen(store: s))),
              if (w < 700) ...[
                    _HeroIcon(Icons.medical_services_outlined, tx('Equipment', 'المعدات'), () => _push(context, EquipmentScreen(store: s))),
                    _HeroIcon(Icons.settings_outlined, tx('Settings & backup', 'الإعدادات والنسخ الاحتياطي'), () => _push(context, SettingsScreen(store: s))),
              ],
            ],
          ),
          const SizedBox(height: 16),
          TileGrid(children: [
            MetricTile(
                label: tx('Items in stock', 'مواد متوفرة'),
                value: '${all.length - low - out}',
                icon: Icons.inventory_2_outlined,
                hint: tx('of ${all.length} active items', 'من ${all.length} مادة فعالة'),
                onTap: () => shell.go('Stock')),
            MetricTile(
                label: tx('Running low', 'قاربت على النفاد'),
                value: '$low',
                icon: Icons.trending_down,
                color: low > 0 ? AppColors.warn : null,
                hint: tx('At or under minimum', 'عند الحد الأدنى أو أقل'),
                onTap: () => shell.go('Stock', 1)),
            MetricTile(
                label: tx('Out of stock', 'نفدت'),
                value: '$out',
                icon: Icons.remove_shopping_cart_outlined,
                color: out > 0 ? AppColors.bad : null,
                hint: tx('Nothing left', 'لم يبقَ شيء'),
                onTap: () => shell.go('Stock', 1)),
            MetricTile(
                label: tx('Issued', 'صُرف'),
                value: '${monthReceipts.length}',
                icon: Icons.outbox_outlined,
                hint: spendTotal > 0 ? tx('This month · ${fmtMoneyShort(spendTotal)}', 'هذا الشهر · ${fmtMoneyShort(spendTotal)}') : tx('Receipts this month', 'وصولات هذا الشهر'),
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
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: expiryCard),
              const SizedBox(width: 16),
              Expanded(child: whereCard),
            ])
          else ...[
            expiryCard,
            const SizedBox(height: 16),
            whereCard,
          ],
          if (insights.isNotEmpty) ...[
            SectionTitle(tx('Needs attention', 'يحتاج انتباهك'), trailing: Text('${insights.length}', style: t.textTheme.labelLarge)),
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
          SectionTitle(tx('Supplies used, last 6 months', 'المواد المصروفة، آخر 6 أشهر')),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: BarChart(
                labels: [for (final m in months) (isAr ? arMonthsShort : names)[m.month - 1]],
                series: [(name: tx('Cost of supplies issued', 'كلفة المواد المصروفة'), color: t.colorScheme.primary, values: used)],
              ),
            ),
          ),
          if (s.invoices.isNotEmpty) ...[
            SectionTitle(tx('Sales', 'المبيعات')),
            TileGrid(wideColumns: 2, children: [
              MetricTile(
                  label: tx('Clients owe you', 'ديون الزبائن لك'),
                  value: fmtMoneyShort(s.owedToUs),
                  icon: Icons.hourglass_bottom,
                  onTap: () => shell.go('Money', 1)),
              MetricTile(
                  label: tx('Sold this month', 'مبيعات هذا الشهر'),
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
    final dep = r.department ?? tx('No department', 'بدون قسم');
    if (cost > 0) out[dep] = (out[dep] ?? 0) + cost;
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
          backgroundColor: Colors.white, foregroundColor: appAccent, minimumSize: const Size(0, 52), textStyle: t.textTheme.labelLarge!.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
      onPressed: onIssue,
      icon: const Icon(Icons.outbox_outlined),
      label: Text(tx('Issue to department', 'صرف إلى قسم')),
    );
    final purchase = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white, side: const BorderSide(color: Colors.white70), minimumSize: const Size(0, 52), textStyle: t.textTheme.labelLarge!.copyWith(fontSize: 16, fontWeight: FontWeight.w600)),
      onPressed: onPurchase,
      icon: const Icon(Icons.add_shopping_cart),
      label: Text(tx('Record purchase', 'تسجيل شراء')),
    );
    return Container(
      padding: EdgeInsets.all(phone ? 20 : 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: heroGradient(),
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
            Text(tx('  · min ${fmtQty(min)}', '  · الأدنى ${fmtQty(min)}'), style: t.textTheme.bodySmall),
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

/// Weekly nudge to export a backup, with the export one tap away.
class BackupReminder extends StatelessWidget {
  const BackupReminder({super.key, required this.store});
  final WarehouseStore store;

  @override
  Widget build(BuildContext context) {
    final d = store.daysSinceBackup;
    final t = Theme.of(context);
    return Card(
      color: AppColors.warn.withValues(alpha: .14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Icon(Icons.backup_outlined, color: AppColors.warn),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    d == null
                        ? tx('No backup yet', 'لا توجد نسخة احتياطية بعد')
                        : tx('Last backup $d days ago', 'آخر نسخة احتياطية قبل $d يوم'),
                    style: t.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700)),
                Text(tx('Save a copy to Files or iCloud Drive once a week.', 'احفظ نسخة في Files أو iCloud Drive مرة كل أسبوع.'),
                    style: t.textTheme.bodySmall),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.end, spacing: 4, runSpacing: 4, children: [
            TextButton(onPressed: store.snoozeBackup, child: Text(tx('Tomorrow', 'غداً'))),
            FilledButton.icon(
              onPressed: () => exportBackup(context, store),
              icon: const Icon(Icons.download),
              label: Text(tx('Back up now', 'نسخ احتياطي الآن')),
            ),
          ]),
        ]),
      ),
    );
  }
}
