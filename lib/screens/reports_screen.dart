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
  late DateTimeRange _range = () {
    final now = DateTime.now();
    return DateTimeRange(start: DateTime(now.year, now.month), end: now);
  }();

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
        child: Row(children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range),
            label: Text('${fmtDate(isoDate(_range.start))} – ${fmtDate(isoDate(_range.end))}'),
            onPressed: () async {
              final r = await showDateRangePicker(
                  context: context, initialDateRange: _range, firstDate: DateTime(2020), lastDate: DateTime(2100));
              if (r != null) setState(() => _range = r);
            },
          ),
          const SizedBox(width: 16),
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

/// Items at or under their minimum, with how much to order to cover two months.
class ReorderScreen extends StatelessWidget {
  const ReorderScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final monthly = store.monthlyIssued();
    final now = DateTime.now();
    final list = store.stockList.where((s) => s.status != StockStatus.inStock).toList()
      ..sort((a, b) => a.qty.compareTo(b.qty));
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
                ? tx('Nothing to reorder. Every item is above its minimum.', 'لا شيء يحتاج إعادة طلب. كل المواد فوق الحد الأدنى.')
                : tx('${list.length} items are at or under their minimum level. The suggestion covers about two months of use.',
                    '${list.length} مادة عند الحد الأدنى أو أقل. الكمية المقترحة تكفي لشهرين تقريباً.'),
            style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 12),
        if (list.isNotEmpty)
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final (i, s) in list.indexed) ...[
                if (i > 0) const Divider(height: 1),
                _ReorderTile(store: store, s: s, avg: avgMonthlyUse(monthly[s.item.id], now)),
              ],
            ]),
          ),
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
