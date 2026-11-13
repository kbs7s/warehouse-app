import 'package:flutter/material.dart';

import '../expiry.dart';
import '../insights.dart';
import '../export.dart';
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
import 'request_screens.dart';
import 'reports_screen.dart' show reorderList;
import 'changes_screen.dart';
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
                  leading: NumberMark(r.no),
                  title: NameText(r.department ?? tx('No department', 'بدون قسم'), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${fmtDate(r.date)} · ${r.lines.length} ${r.lines.length == 1 ? tx('item', 'مادة') : tx('items', 'مواد')}'),
                  trailing: const Icon(Icons.chevron_right),
                ),
            ]),
    );

    final staff = s.cloud?.isStaff ?? false;
    final phone = isPhone(context);
    String itemsWord(int n) => n == 1 ? tx('item', 'مادة') : tx('items', 'مواد');

    // Everything waiting on the owner, in one card: department requests, team issues to check, the backup.
    final waiting = <Widget>[
      if (s.openRequests.isNotEmpty) ...[
        _SubHead(tx('Department requests (${s.openRequests.length})', 'طلبات الأقسام (${s.openRequests.length})'),
            action: (tx('See all', 'عرض الكل'), () => shell.go('Issue', 1))),
        for (final r in s.openRequests.take(4))
          _Row(
            lead: NumberMark(r.no, color: t.colorScheme.primary),
            title: r.department ?? tx('No department', 'بدون قسم'),
            sub: '${fmtDate(r.date)} · ${r.lines.length} ${itemsWord(r.lines.length)}',
            onTap: () => openRequest(context, s, r),
            trailing: Text(tx('Issue', 'صرف'), style: TextStyle(color: t.colorScheme.primary, fontWeight: FontWeight.w700)),
          ),
      ],
      if (!staff && s.toReview.isNotEmpty) ...[
        _SubHead(tx('Team issues to review (${s.toReview.length})', 'صرفيات الكادر للمراجعة (${s.toReview.length})')),
        for (final r in s.toReview.take(4))
          _Row(
            lead: NumberMark(r.no, color: t.colorScheme.warning),
            title: r.department ?? tx('No department', 'بدون قسم'),
            sub: '${fmtDate(r.date)} · ${r.lines.length} ${itemsWord(r.lines.length)}${r.by == null ? '' : ' · ${r.by}'}',
            onTap: () => openReceipt(context, s, r),
            trailing: TextButton(onPressed: () => s.approveReceipt(r.no), child: Text(tx('Approve', 'اعتماد'))),
          ),
      ],
      if (s.backupDue && !staff) ...[
        _SubHead(s.daysSinceBackup == null
            ? tx('No backup yet', 'لا توجد نسخة احتياطية بعد')
            : tx('Last backup ${s.daysSinceBackup} days ago', 'آخر نسخة احتياطية قبل ${s.daysSinceBackup} يوم')),
        Text(tx('Save a copy to Files or iCloud Drive once a week.', 'احفظ نسخة في Files أو iCloud Drive مرة كل أسبوع.'),
            style: TextStyle(color: t.colorScheme.onSurface)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          OutlinedButton.icon(onPressed: () => exportBackup(context, s), icon: const Icon(Icons.download), label: Text(tx('Back up now', 'نسخ احتياطي الآن'))),
          TextButton(onPressed: s.snoozeBackup, child: Text(tx('Tomorrow', 'غداً'))),
        ]),
      ],
    ];
    final waitingCard = waiting.isEmpty
        ? null
        : Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(tx('Waiting for you', 'بانتظارك'), style: t.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w800)),
                ...waiting,
              ]),
            ),
          );

    final issueBtn = FilledButton.icon(
      style: FilledButton.styleFrom(minimumSize: const Size(0, 52), textStyle: t.textTheme.labelLarge!.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
      onPressed: () => openReceipt(context, s, null),
      icon: const Icon(Icons.outbox_outlined),
      label: Text(tx('Issue to department', 'صرف إلى قسم')),
    );
    final purchaseBtn = OutlinedButton.icon(
      // On the page background the theme's grey fill disappears, so this one sits on the card colour with an edge.
      style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 52),
          backgroundColor: t.cardTheme.color ?? t.colorScheme.surfaceContainerLowest,
          side: BorderSide(color: t.colorScheme.outline),
          textStyle: t.textTheme.labelLarge!.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
      onPressed: () => openPurchase(context, s, null),
      icon: const Icon(Icons.add_shopping_cart),
      label: Text(tx('Record purchase', 'تسجيل شراء')),
    );
    final icons = <Widget>[
      if (!staff) IconButton(tooltip: tx('Export everything to Excel', 'تصدير كل البيانات إلى إكسل'), onPressed: () => exportExcel(s), icon: const Icon(Icons.table_view_outlined)),
      ChangesBell(store: s),
      SyncBadge(store: s, onTap: () => _push(context, SettingsScreen(store: s))),
      if (w < 700) ...[
        IconButton(tooltip: tx('Reserve store', 'مخزن الاحتياط'), onPressed: () => shell.go('Reserve'), icon: const Icon(Icons.warehouse_outlined)),
        IconButton(tooltip: tx('Equipment', 'المعدات'), onPressed: () => _push(context, EquipmentScreen(store: s)), icon: const Icon(Icons.medical_services_outlined)),
        IconButton(tooltip: tx('Settings & backup', 'الإعدادات والنسخ الاحتياطي'), onPressed: () => _push(context, SettingsScreen(store: s)), icon: const Icon(Icons.settings_outlined)),
      ],
    ];

    // Cards after the figures, two to a row on wide screens; an odd one out takes the full width.
    final cards = <Widget>[?waitingCard, reorderCard, recentCard, expiryCard, whereCard];
    final grid = <Widget>[];
    if (wide) {
      for (var i = 0; i < cards.length; i += 2) {
        grid.add(i + 1 < cards.length
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: cards[i]),
                const SizedBox(width: 16),
                Expanded(child: cards[i + 1]),
              ])
            : cards[i]);
        grid.add(const SizedBox(height: 16));
      }
    } else {
      for (final c in cards) {
        grid..add(c)..add(const SizedBox(height: 12));
      }
    }

    return Scaffold(
      body: SafeArea(
        child: PageBody(children: [
          const SizedBox(height: 8),
          // The title row: the store's name and today's date, with the header icons.
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                NameText(s.companyName.isEmpty ? 'قسم التجهيز' : s.companyName,
                    style: t.textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w800, fontSize: phone ? 22 : 26)),
                Text('$_greeting · ${fmtDate(todayIso())}', style: TextStyle(color: t.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
              ]),
            ),
            ...icons,
          ]),
          const SizedBox(height: 16),
          if (phone)
            Row(children: [Expanded(child: issueBtn), const SizedBox(width: 10), Expanded(child: purchaseBtn)])
          else
            Row(children: [issueBtn, const SizedBox(width: 12), purchaseBtn]),
          const SizedBox(height: 16),
          _Figures(children: [
            _Figure(tx('Items in stock', 'مواد متوفرة'), '${all.length - low - out}', tx('of ${all.length} active items', 'من ${all.length} مادة فعالة'),
                onTap: () => shell.go('Stock')),
            _Figure(tx('Running low', 'قاربت على النفاد'), '$low', tx('At or under minimum', 'عند الحد الأدنى أو أقل'),
                color: low > 0 ? t.colorScheme.warning : null, onTap: () => shell.go('Stock', 1)),
            _Figure(tx('Out of stock', 'نفدت'), '$out', tx('Nothing left', 'لم يبقَ شيء'),
                color: out > 0 ? t.colorScheme.bad : null, onTap: () => shell.go('Stock', 1)),
            _Figure(
                tx('Issued this month', 'صرف هذا الشهر'),
                '${monthReceipts.length}',
                spendTotal > 0 ? tx('Receipts · ${fmtMoneyShort(spendTotal)}', 'وصل · ${fmtMoneyShort(spendTotal)}') : tx('Receipts', 'وصل'),
                onTap: () => shell.go('Issue')),
          ]),
          const SizedBox(height: 16),
          ...grid,
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
              MetricTile(label: tx('Clients owe you', 'ديون الزبائن لك'), value: fmtMoneyShort(s.owedToUs), onTap: () => shell.go('Money', 1)),
              MetricTile(label: tx('Sold this month', 'مبيعات هذا الشهر'), value: fmtMoneyShort(s.profit(from, to).sales), onTap: () => shell.go('Money', 1)),
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

/// The four stock figures in one divided card: a label, a number and a note each, no icons.
class _Figures extends StatelessWidget {
  const _Figures({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.outlineVariant;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= 560) {
          return IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (i, f) in children.indexed) ...[
                if (i > 0) VerticalDivider(width: 1, color: line),
                Expanded(child: f),
              ],
            ]),
          );
        }
        // Phones: two by two.
        Widget pair(int i) => IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: children[i]),
                VerticalDivider(width: 1, color: line),
                Expanded(child: children[i + 1]),
              ]),
            );
        return Column(children: [pair(0), Divider(height: 1, color: line), pair(2)]);
      }),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, this.note, {this.color, this.onTap});
  final String label, value, note;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: t.colorScheme.onSurfaceVariant), overflow: TextOverflow.ellipsis),
          Text(value,
              style: TextStyle(
                  fontSize: 30, height: 1.25, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()], color: color ?? t.colorScheme.onSurface)),
          Text(note, style: t.textTheme.bodySmall!.copyWith(color: t.colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

/// A small heading inside the "Waiting for you" card.
class _SubHead extends StatelessWidget {
  const _SubHead(this.text, {this.action});
  final String text;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(children: [
          Expanded(
              child: Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant))),
          if (action != null) TextButton(onPressed: action!.$2, child: Text(action!.$1)) else const SizedBox(height: 40),
        ]),
      );
}

/// One line in the "Waiting for you" card.
class _Row extends StatelessWidget {
  const _Row({required this.lead, required this.title, required this.sub, required this.onTap, this.trailing});
  final Widget lead;
  final String title, sub;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            lead,
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                NameText(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
                Text(sub, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
              ]),
            ),
            ?trailing,
          ]),
        ),
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
            TextButton(style: TextButton.styleFrom(foregroundColor: t.colorScheme.onSurface), onPressed: store.snoozeBackup, child: Text(tx('Tomorrow', 'غداً'))),
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
