import 'package:flutter/material.dart';

import '../export.dart';
import '../l10n.dart';
import '../models.dart';
import '../shell.dart';
import '../store.dart';
import '../ui.dart';
import 'item_screens.dart';

PreferredSizeWidget _bottom(BuildContext context) {
  final nav = SubNav.bar(context);
  final tabs = TabBar(tabs: [Tab(text: tx('Monthly use', 'الاستهلاك الشهري')), Tab(text: tx('By department', 'حسب القسم'))]);
  if (nav == null) return tabs;
  return PreferredSize(
    preferredSize: Size.fromHeight(nav.preferredSize.height + tabs.preferredSize.height),
    child: Column(children: [nav, tabs]),
  );
}

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: Text(tx('Reports', 'التقارير')),
            actions: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: FilledButton.icon(
                  onPressed: () => exportExcel(store),
                  icon: const Icon(Icons.table_view),
                  label: Text(tx('Export to Excel', 'تصدير إلى إكسل')),
                ),
              ),
            ],
            bottom: _bottom(context),
          ),
          body: TabBarView(children: [
            _MonthlyUse(store: store),
            _ByDepartment(store: store),
          ]),
        ),
      );
}

/// Wide table that scrolls both ways; first column holds Arabic item names.
class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.rows});
  final List<String> columns;
  final List<(Item, List<num>)> rows;

  @override
  Widget build(BuildContext context) => Scrollbar(
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(16),
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 40,
              dataRowMaxHeight: 44,
              columnSpacing: 20,
              columns: [
                DataColumn(label: Text(tx('Item', 'المادة'))),
                for (final c in columns) DataColumn(label: NameText(c), numeric: true),
              ],
              rows: [
                for (final (item, values) in rows)
                  DataRow(cells: [
                    DataCell(SizedBox(width: 220, child: NameText(item.name))),
                    for (final (i, v) in values.indexed)
                      DataCell(Text(v == 0 ? '·' : fmtQty(v),
                          style: TextStyle(
                              fontWeight: i == values.length - 1 ? FontWeight.w700 : null,
                              color: v == 0 ? Colors.grey : null))),
                  ]),
              ],
            ),
          ),
        ),
      );
}

class _MonthlyUse extends StatefulWidget {
  const _MonthlyUse({required this.store});
  final WarehouseStore store;
  @override
  State<_MonthlyUse> createState() => _MonthlyUseState();
}

class _MonthlyUseState extends State<_MonthlyUse> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final monthly = widget.store.monthlyIssued();
    final months = lastMonths(DateTime.now());
    final rows = <(Item, List<num>)>[
      for (final i in widget.store.activeItems)
        if (_q.trim().isEmpty || i.name.contains(_q.trim()))
          (i, [for (final m in months) monthly[i.id]?[m] ?? 0, months.fold<num>(0, (t, m) => t + (monthly[i.id]?[m] ?? 0))]),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(children: [
          Expanded(child: SearchField(onChanged: (v) => setState(() => _q = v), hint: tx('Filter items', 'ابحث في المواد'))),
          const SizedBox(width: 16),
          Flexible(
              child: Text(
                  tx('Quantity issued per month. Months before the app use the Excel Year sheet.',
                      'الكمية المصروفة في كل شهر. الأشهر قبل التطبيق مأخوذة من ورقة السنة في إكسل.'),
                  style: const TextStyle(color: Colors.grey))),
        ]),
      ),
      Expanded(child: _Grid(columns: [...months.map(monthLabel), tx('Total', 'المجموع')], rows: rows)),
    ]);
  }
}

class _ByDepartment extends StatefulWidget {
  const _ByDepartment({required this.store});
  final WarehouseStore store;
  @override
  State<_ByDepartment> createState() => _ByDepartmentState();
}

class _ByDepartmentState extends State<_ByDepartment> {
  // This month, or last month while nothing has been issued yet this month.
  late DateTimeRange _range = () {
    final p = widget.store.issuedByDepartment(Period.thisMonth.range().$1, Period.thisMonth.range().$2).isEmpty
        ? Period.lastMonth
        : Period.thisMonth;
    return _rangeOf(p);
  }();

  static DateTimeRange _rangeOf(Period p) {
    final (a, b) = p.range();
    final n = DateTime.now();
    if (p == Period.allTime) return DateTimeRange(start: DateTime(2020), end: DateTime(n.year, n.month, n.day));
    return DateTimeRange(start: DateTime.parse(a), end: DateTime.parse(b));
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.store.issuedByDepartment(isoDate(_range.start), isoDate(_range.end));
    final depts = data.keys.toList()..sort();
    final ids = {for (final d in data.values) ...d.keys};
    final rows = <(Item, List<num>)>[
      for (final i in widget.store.items)
        if (ids.contains(i.id))
          (i, [for (final d in depts) data[d]![i.id] ?? 0, depts.fold<num>(0, (t, d) => t + (data[d]![i.id] ?? 0))]),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final p in Period.values)
            ChoiceChip(
              label: Text(p.label),
              showCheckmark: false,
              selected: _rangeOf(p) == _range,
              onSelected: (_) => setState(() => _range = _rangeOf(p)),
            ),
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range),
            label: Text('${fmtDate(isoDate(_range.start))} – ${fmtDate(isoDate(_range.end))}'),
            onPressed: () async {
              final r = await showDateRangePicker(
                  context: context, initialDateRange: _range, firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (r != null) setState(() => _range = r);
            },
          ),
          Text(tx('${rows.length} items issued to ${depts.length} departments', '${rows.length} مادة صُرفت إلى ${depts.length} قسم'),
              style: const TextStyle(color: Colors.grey)),
        ]),
      ),
      Expanded(
        child: rows.isEmpty
            ? Center(child: Text(tx('No receipts in these dates.', 'لا يوجد صرف في هذه التواريخ.')))
            : _Grid(columns: [...depts, tx('Total', 'المجموع')], rows: rows),
      ),
    ]);
  }
}

/// Items that need ordering: at or under their minimum and still in use (a minimum is set or the item
/// was issued in the last three months). Out of stock first, then the most used.
/// With [dormant], the opposite: empty or low items nobody has used lately and with no minimum set.
List<(StockInfo, num)> reorderList(WarehouseStore store, {bool dormant = false}) {
  final monthly = store.monthlyIssued();
  final now = DateTime.now();
  final out = <(StockInfo, num)>[
    for (final s in store.stockList)
      if (s.status != StockStatus.inStock)
        if (avgMonthlyUse(monthly[s.item.id], now) case final avg when (s.item.minLevel <= 0 && avg <= 0) == dormant) (s, avg),
  ];
  int rank(StockInfo s) => s.status == StockStatus.out ? 0 : 1;
  out.sort((a, b) {
    final r = rank(a.$1).compareTo(rank(b.$1));
    return r != 0 ? r : b.$2.compareTo(a.$2);
  });
  return out;
}

/// Items at or under their minimum, with how much to order to cover two months.
class ReorderScreen extends StatelessWidget {
  const ReorderScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final list = reorderList(store);
    final dormant = reorderList(store, dormant: true);
    Widget card(List<(StockInfo, num)> l) => Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final (i, (s, avg)) in l.indexed) ...[
              if (i > 0) const Divider(height: 1),
              _ReorderTile(store: store, s: s, avg: avg),
            ],
          ]),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(tx('Reorder', 'إعادة الطلب')),
        bottom: SubNav.bar(context),
        actions: [
          IconButton(tooltip: tx('Export to Excel', 'تصدير إلى إكسل'), icon: const Icon(Icons.table_view_outlined), onPressed: () => exportExcel(store)),
          const SizedBox(width: 8),
        ],
      ),
      body: PageBody(children: [
        Text(
            list.isEmpty
                ? tx('Nothing to reorder. Every item in use is above its minimum.', 'لا شيء يحتاج إعادة طلب. كل المواد المستخدمة فوق الحد الأدنى.')
                : tx('${list.length} items in use are at or under their minimum, out of stock first. The suggestion covers about two months of use.',
                    '${list.length} مادة مستخدمة عند الحد الأدنى أو أقل، النافدة أولاً. الكمية المقترحة تكفي لشهرين تقريباً.'),
            style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        if (list.isNotEmpty) card(list),
        if (dormant.isNotEmpty) ...[
          SectionTitle(tx('Empty, but not used lately', 'نافدة لكن غير مستخدمة مؤخراً'), trailing: Text('${dormant.length}')),
          Text(
              tx('No minimum is set and nothing was issued in the last three months. Set a minimum on an item to move it up.',
                  'لا يوجد حد أدنى ولم يُصرف منها شيء خلال آخر ثلاثة أشهر. حدّد حداً أدنى للمادة لتظهر في الأعلى.'),
              style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          card(dormant),
        ],
      ]),
    );
  }
}

class _ReorderTile extends StatelessWidget {
  const _ReorderTile({required this.store, required this.s, required this.avg});
  final WarehouseStore store;
  final StockInfo s;
  final num avg;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final target = [s.item.minLevel * 2, avg * 2].reduce((a, b) => a > b ? a : b);
    final suggest = (target - (s.qty < 0 ? 0 : s.qty)).ceil();
    return ListTile(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ItemDetailScreen(store: store, itemId: s.item.id))),
      title: NameText(s.item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(tx('${s.item.id} · in stock ${fmtQty(s.qty)} · min ${fmtQty(s.item.minLevel)} · uses ~${fmtQty(avg.round())}/month',
          '${s.item.id} · الموجود ${fmtQty(s.qty)} · الحد الأدنى ${fmtQty(s.item.minLevel)} · الاستهلاك ~${fmtQty(avg.round())}/شهر')),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        if (suggest > 0) Text(tx('Order $suggest', 'اطلب $suggest'), style: t.textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        StatusChip(s.status),
      ]),
    );
  }
}
