import 'package:flutter/material.dart';

import '../export.dart';
import '../models.dart';
import '../shell.dart';
import '../store.dart';
import '../ui.dart';

PreferredSizeWidget _bottom(BuildContext context) {
  final nav = SubNav.bar(context);
  const tabs = TabBar(tabs: [Tab(text: 'Monthly use'), Tab(text: 'By department'), Tab(text: 'Reorder list')]);
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
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Reports'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilledButton.icon(
                  onPressed: () => exportExcel(store),
                  icon: const Icon(Icons.table_view),
                  label: const Text('Export to Excel'),
                ),
              ),
            ],
            bottom: _bottom(context),
          ),
          body: TabBarView(children: [
            _MonthlyUse(store: store),
            _ByDepartment(store: store),
            _Reorder(store: store),
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
                const DataColumn(label: Text('Item')),
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
          Expanded(child: SearchField(onChanged: (v) => setState(() => _q = v), hint: 'Filter items')),
          const SizedBox(width: 16),
          const Flexible(
              child: Text('Quantity issued per month. Months before the app use the Excel Year sheet.',
                  style: TextStyle(color: Colors.grey))),
        ]),
      ),
      Expanded(child: _Grid(columns: [...months.map(monthLabel), 'Total'], rows: rows)),
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
          Text('${rows.length} items issued to ${depts.length} departments', style: const TextStyle(color: Colors.grey)),
        ]),
      ),
      Expanded(
        child: rows.isEmpty
            ? const Center(child: Text('No receipts in these dates.'))
            : _Grid(columns: [...depts, 'Total'], rows: rows),
      ),
    ]);
  }
}

class _Reorder extends StatelessWidget {
  const _Reorder({required this.store});
  final WarehouseStore store;

  @override
  Widget build(BuildContext context) {
    final monthly = store.monthlyIssued();
    final now = DateTime.now();
    final list = store.stockList.where((s) => s.status != StockStatus.inStock).toList()
      ..sort((a, b) => a.qty.compareTo(b.qty));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('${list.length} items are at or below their minimum level.', style: const TextStyle(color: Colors.grey)),
      DataTable(
        columns: const [
          DataColumn(label: Text('Code')),
          DataColumn(label: Text('Item')),
          DataColumn(label: Text('Unit')),
          DataColumn(label: Text('In stock'), numeric: true),
          DataColumn(label: Text('Minimum'), numeric: true),
          DataColumn(label: Text('Avg use / month'), numeric: true),
          DataColumn(label: Text('Status')),
        ],
        rows: [
          for (final s in list)
            DataRow(cells: [
              DataCell(Text(s.item.id)),
              DataCell(NameText(s.item.name)),
              DataCell(NameText(s.item.unit)),
              DataCell(Text(fmtQty(s.qty), style: const TextStyle(fontWeight: FontWeight.w600))),
              DataCell(Text(fmtQty(s.item.minLevel))),
              DataCell(Text(fmtQty(avgMonthlyUse(monthly[s.item.id], now).round()))),
              DataCell(StatusChip(s.status)),
            ]),
        ],
      ),
    ]);
  }
}
