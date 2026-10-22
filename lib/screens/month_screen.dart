import 'package:flutter/material.dart';

import '../l10n.dart';
import '../month.dart';
import '../platform/files.dart';
import '../shell.dart';
import '../store.dart';
import '../theme.dart';
import '../ui.dart';
import '../xlsx.dart';
import 'item_screens.dart';

String _monthName(String iso) {
  final d = DateTime.parse(iso);
  const en = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  return '${isAr ? arMonths[d.month - 1] : en[d.month - 1]} ${d.year}';
}

/// "October 2026" for a whole calendar month, otherwise "3 Oct 2026 – 28 Oct 2026".
String monthTitle(String from, String to) {
  final a = DateTime.parse(from), b = DateTime.parse(to);
  final whole = a.day == 1 && a.year == b.year && a.month == b.month && DateTime(b.year, b.month, b.day + 1).month != b.month;
  return whole || fmtMonth(from) == fmtMonth(to) ? fmtMonth(from) : '${fmtMonth(from)} – ${fmtMonth(to)}';
}

num _sum(Iterable<num> v) => v.fold<num>(0, (a, b) => a + b);

Future<void> _exportMonth(String title, String file, List<MonthRow> rows, {Map<String, num>? year}) async {
  final sheet = Sheet(
    tx('Month', 'الشهر'),
    [
      tx('Code', 'الرمز'), tx('Item', 'المادة'), tx('Unit', 'الوحدة'), tx('Start of month', 'أول الشهر'), tx('Received', 'الوارد'),
      tx('Issued (spend)', 'المصروف'), if (year != null) tx('Issued this year', 'مصروف السنة'), tx('End of month', 'آخر الشهر'),
    ],
    [
      [title],
      for (final r in rows)
        [r.itemId, r.name, r.unit, r.opening, r.received, r.issued, if (year != null) year[r.itemId] ?? 0, r.closing],
    ],
    rightToLeft: isAr,
  );
  await downloadFile(file, buildXlsx([sheet]), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
}

/// The open month: what each item started with, received and spent, its stock now, and the
/// button that saves the month and starts a new one.
class MonthScreen extends StatefulWidget {
  const MonthScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  State<MonthScreen> createState() => _MonthScreenState();
}

class _MonthScreenState extends State<MonthScreen> {
  bool _all = false;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final t = Theme.of(context);
    final from = s.openMonthStart;
    final today = todayIso();
    final to = today.compareTo(from) < 0 ? from : today;
    final rows = s.monthRows(from, '9999-12-31');
    final year = s.spentThisYear;
    final moved = rows.where(rowMoved).toList();
    final shown = [
      for (final r in (_all ? rows : moved))
        if (_q.isEmpty || r.name.contains(_q) || r.itemId.toLowerCase().contains(_q.toLowerCase())) r
    ];
    final receiptCount = s.receiptsBetween(from, '9999-12-31');

    return Scaffold(
      appBar: AppBar(
        title: Text(tx('Month end', 'نهاية الشهر')),
        bottom: SubNav.bar(context),
        actions: [
          IconButton(
            tooltip: tx('Export to Excel', 'تصدير إلى إكسل'),
            icon: const Icon(Icons.table_view_outlined),
            onPressed: () => _exportMonth(monthTitle(from, to), 'month-$from.xlsx', rows, year: year),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: PageBody(children: [
        _OpenMonthCard(store: s, from: from, to: to),
        const SizedBox(height: 14),
        TileGrid(children: [
          MetricTile(
              label: tx('Spent this month', 'مصروف الشهر'),
              value: fmtQty(_sum(moved.map((r) => r.issued))),
              icon: Icons.outbox_outlined,
              hint: tx('Units · $receiptCount receipts', 'وحدة · $receiptCount وصل')),
          MetricTile(
              label: tx('Spent this year', 'مصروف السنة'),
              value: fmtQty(_sum(year.values)),
              icon: Icons.calendar_month_outlined,
              hint: tx('Units since 1 January', 'وحدة منذ 1 كانون الثاني')),
          MetricTile(
              label: tx('Received this month', 'وارد الشهر'),
              value: fmtQty(_sum(moved.map((r) => r.received))),
              icon: Icons.move_to_inbox_outlined,
              hint: tx('Units bought', 'وحدة مشتراة')),
          MetricTile(
              label: tx('Items moved', 'مواد تحركت'),
              value: '${moved.length}',
              icon: Icons.swap_vert,
              hint: tx('of ${rows.length} items', 'من ${rows.length} مادة')),
        ]),
        SectionTitle(tx('Items this month', 'المواد هذا الشهر'), trailing: Text('${shown.length}')),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ChoiceChip(
              label: Text(tx('Moved this month', 'تحركت هذا الشهر')),
              selected: !_all,
              showCheckmark: false,
              onSelected: (_) => setState(() => _all = false)),
          ChoiceChip(
              label: Text(tx('All items', 'كل المواد')), selected: _all, showCheckmark: false, onSelected: (_) => setState(() => _all = true)),
          SizedBox(width: 280, child: SearchField(onChanged: (v) => setState(() => _q = v.trim()))),
        ]),
        const SizedBox(height: 12),
        MonthTable(store: s, rows: shown, year: year, emptyText: tx('Nothing issued or received yet this month.', 'لم يُصرف أو يرد شيء بعد هذا الشهر.')),
        if (s.monthCloses.isNotEmpty) ...[
          SectionTitle(tx('Past months', 'الأشهر السابقة'), trailing: Text('${s.monthCloses.length}')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final (i, m) in s.monthCloses.reversed.indexed) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  leading: CircleAvatar(
                      backgroundColor: t.colorScheme.secondaryContainer,
                      child: Icon(Icons.event_available, color: t.colorScheme.onSecondaryContainer, size: 20)),
                  title: Text(monthTitle(m.from, m.to), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(tx('Spent ${fmtQty(m.issued)} units · ${m.receipts} receipts', 'المصروف ${fmtQty(m.issued)} وحدة · ${m.receipts} وصل')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ClosedMonthScreen(store: s, month: m))),
                ),
              ],
            ]),
          ),
        ],
      ]),
    );
  }
}

class _OpenMonthCard extends StatelessWidget {
  const _OpenMonthCard({required this.store, required this.from, required this.to});
  final WarehouseStore store;
  final String from, to;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final phone = isPhone(context);
    final close = FilledButton.icon(
      style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.brand,
          minimumSize: const Size(0, 52),
          textStyle: t.textTheme.labelLarge!.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
      onPressed: () => _closeMonth(context),
      icon: const Icon(Icons.event_available),
      label: Text(tx('Close month & start new', 'إغلاق الشهر وبدء شهر جديد')),
    );
    return Container(
      padding: EdgeInsets.all(phone ? 20 : 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F766E), Color(0xFF115E59), Color(0xFF134E4A)],
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tx('Open month', 'الشهر المفتوح'), style: t.textTheme.labelLarge!.copyWith(color: Colors.white70)),
        const SizedBox(height: 4),
        Text(fmtMonth(from),
            style: t.textTheme.headlineSmall!.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
            tx('Spend counts from this date. At month end, close the month to save every item\'s spend and stock and start again from zero.',
                'يُحسب الصرف من هذا التاريخ. في نهاية الشهر أغلق الشهر لحفظ صرف ورصيد كل مادة والبدء من الصفر.'),
            style: t.textTheme.bodyMedium!.copyWith(color: Colors.white70)),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (phone) SizedBox(width: double.infinity, child: close) else close,
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () async {
              final d = await showDatePicker(
                  context: context, initialDate: DateTime.parse(from), firstDate: DateTime(2020), lastDate: DateTime.now());
              if (d != null) store.setOpenMonthStart(isoDate(d));
            },
            icon: const Icon(Icons.edit_calendar_outlined),
            label: Text(tx('Change start date', 'تغيير تاريخ البداية')),
          ),
        ]),
      ]),
    );
  }

  Future<void> _closeMonth(BuildContext context) async {
    // Default end: the last day of the start's month once that month is over, otherwise today.
    final start = DateTime.parse(from);
    final monthEnd = DateTime(start.year, start.month + 1, 0);
    final now = DateTime.now();
    var end = now.isAfter(monthEnd) ? monthEnd : DateTime(now.year, now.month, now.day);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text(tx('Close the month?', 'إغلاق الشهر؟')),
          content: SizedBox(
            width: 440,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(tx(
                  'This saves, for every item, the stock at the start, what was received, what was spent and the stock at the end. '
                      'Then spend starts again from zero. Stock itself does not change.',
                  'سيُحفظ لكل مادة رصيد أول الشهر والوارد والمصروف ورصيد آخر الشهر. '
                      'بعدها يبدأ الصرف من الصفر. الرصيد نفسه لا يتغيّر.')),
              const SizedBox(height: 16),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(context: c, initialDate: end, firstDate: start, lastDate: DateTime(2100));
                  if (d != null) setState(() => end = d);
                },
                child: InputDecorator(
                  decoration: InputDecoration(labelText: tx('Last day of this month', 'آخر يوم في هذا الشهر')),
                  child: Text('${fmtDate(from)} – ${fmtDate(isoDate(end))}'),
                ),
              ),
              if (end.isBefore(monthEnd)) ...[
                const SizedBox(height: 8),
                Text(
                    tx('${_monthName(from)} is not over yet. Close now only if this month is done.',
                        '${_monthName(from)} لم ينتهِ بعد. أغلقه الآن فقط إذا انتهى عمل هذا الشهر.'),
                    style: Theme.of(c).textTheme.bodySmall!.copyWith(color: AppColors.warn, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 8),
              Text(tx('The new month starts on ${fmtDate(isoDate(end.add(const Duration(days: 1))))}.',
                  'يبدأ الشهر الجديد في ${fmtDate(isoDate(end.add(const Duration(days: 1))))}.'),
                  style: Theme.of(c).textTheme.bodySmall),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tx('Cancel', 'إلغاء'))),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tx('Close month', 'إغلاق الشهر'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final m = store.closeMonth(to: isoDate(end));
    if (context.mounted) {
      toast(context, tx('${monthTitle(m.from, m.to)} saved. A new month has started.', 'حُفظ ${monthTitle(m.from, m.to)}. بدأ شهر جديد.'));
    }
  }
}

/// A saved month, read-only, with Excel export and (for the latest one) reopen.
class ClosedMonthScreen extends StatelessWidget {
  const ClosedMonthScreen({super.key, required this.store, required this.month});
  final WarehouseStore store;
  final MonthClose month;

  @override
  Widget build(BuildContext context) {
    final m = month;
    final title = monthTitle(m.from, m.to);
    final moved = m.rows.where(rowMoved).toList();
    final isLast = store.monthCloses.isNotEmpty && identical(store.monthCloses.last, m);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: tx('Export to Excel', 'تصدير إلى إكسل'),
            icon: const Icon(Icons.table_view_outlined),
            onPressed: () => _exportMonth(title, 'month-${m.from}.xlsx', m.rows),
          ),
          if (isLast)
            PopupMenuButton<String>(
              onSelected: (_) async {
                if (await confirm(
                    context,
                    tx('Reopen $title?', 'إعادة فتح $title؟'),
                    tx('The saved figures for this month are removed and it becomes the open month again.',
                        'تُحذف الأرقام المحفوظة لهذا الشهر ويعود الشهر المفتوح.'),
                    action: tx('Reopen', 'إعادة فتح'))) {
                  store.reopenLastMonth();
                  if (context.mounted) Navigator.pop(context);
                }
              },
              itemBuilder: (_) => [PopupMenuItem(value: 'reopen', child: Text(tx('Reopen this month', 'إعادة فتح هذا الشهر')))],
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: PageBody(children: [
        TileGrid(children: [
          MetricTile(label: tx('Spent', 'المصروف'), value: fmtQty(m.issued), icon: Icons.outbox_outlined, hint: tx('Units · ${m.receipts} receipts', 'وحدة · ${m.receipts} وصل')),
          MetricTile(label: tx('Received', 'الوارد'), value: fmtQty(m.received), icon: Icons.move_to_inbox_outlined, hint: tx('Units bought', 'وحدة مشتراة')),
          MetricTile(label: tx('Items moved', 'مواد تحركت'), value: '${moved.length}', icon: Icons.swap_vert, hint: tx('of ${m.rows.length} items', 'من ${m.rows.length} مادة')),
          MetricTile(
              label: tx('Closed on', 'أُغلق في'),
              value: m.closedAt.length >= 10 ? fmtDate(m.closedAt.substring(0, 10)) : '—',
              icon: Icons.event_available,
              hint: monthTitle(m.from, m.to)),
        ]),
        SectionTitle(tx('Items', 'المواد'), trailing: Text('${m.rows.length}')),
        MonthTable(store: store, rows: [...moved, ...m.rows.where((r) => !rowMoved(r))], emptyText: tx('No items.', 'لا توجد مواد.')),
      ]),
    );
  }
}

/// Item rows: start of month, received, spent, (spent this year), end of month.
class MonthTable extends StatelessWidget {
  const MonthTable({super.key, required this.store, required this.rows, this.year, required this.emptyText});
  final WarehouseStore store;
  final List<MonthRow> rows;
  final Map<String, num>? year;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    if (rows.isEmpty) return Card(child: ListTile(leading: const Icon(Icons.inbox_outlined), title: Text(emptyText)));
    final wide = MediaQuery.sizeOf(context).width >= 760;
    void open(MonthRow r) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ItemDetailScreen(store: store, itemId: r.itemId)));
    final muted = t.textTheme.bodySmall!.copyWith(color: t.colorScheme.onSurfaceVariant);
    final bold = const TextStyle(fontWeight: FontWeight.w700);
    Widget num0(num v, {TextStyle? style, String sign = ''}) =>
        SizedBox(width: 84, child: Text(v == 0 ? '·' : '$sign${fmtQty(v)}', textAlign: TextAlign.end, style: style));

    if (!wide) {
      return Card(
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          for (final (i, r) in rows.indexed) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              onTap: () => open(r),
              title: NameText(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                  [
                    tx('Start ${fmtQty(r.opening)}', 'البداية ${fmtQty(r.opening)}'),
                    tx('in ${fmtQty(r.received)}', 'وارد ${fmtQty(r.received)}'),
                    tx('spent ${fmtQty(r.issued)}', 'مصروف ${fmtQty(r.issued)}'),
                    if (year != null) tx('year ${fmtQty(year![r.itemId] ?? 0)}', 'السنة ${fmtQty(year![r.itemId] ?? 0)}'),
                  ].join(' · '),
                  style: muted),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(fmtQty(r.closing), style: bold.copyWith(fontSize: 16, color: r.closing <= 0 ? AppColors.bad : null)),
                Text(r.unit, style: muted),
              ]),
            ),
          ],
        ]),
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: DefaultTextStyle.merge(
            style: muted.copyWith(fontWeight: FontWeight.w600),
            child: Row(children: [
              Expanded(child: Text(tx('Item', 'المادة'))),
              SizedBox(width: 84, child: Text(tx('Start', 'البداية'), textAlign: TextAlign.end)),
              SizedBox(width: 84, child: Text(tx('Received', 'الوارد'), textAlign: TextAlign.end)),
              SizedBox(width: 84, child: Text(tx('Spent', 'المصروف'), textAlign: TextAlign.end)),
              if (year != null) SizedBox(width: 84, child: Text(tx('This year', 'السنة'), textAlign: TextAlign.end)),
              SizedBox(width: 84, child: Text(tx('End', 'النهاية'), textAlign: TextAlign.end)),
            ]),
          ),
        ),
        for (final r in rows) ...[
          const Divider(height: 1),
          InkWell(
            onTap: () => open(r),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    NameText(r.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${r.itemId} · ${r.unit}', style: muted),
                  ]),
                ),
                num0(r.opening),
                num0(r.received, style: const TextStyle(color: AppColors.good), sign: '+'),
                num0(r.issued, style: bold.copyWith(color: AppColors.warn)),
                if (year != null) num0(year![r.itemId] ?? 0, style: muted),
                SizedBox(
                    width: 84,
                    child: Text(fmtQty(r.closing),
                        textAlign: TextAlign.end, style: bold.copyWith(color: r.closing <= 0 ? AppColors.bad : null))),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}
