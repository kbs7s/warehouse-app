import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';
import '../month.dart';
import '../shell.dart';
import '../store.dart';
import '../ui.dart';
import 'item_screens.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  String _query = '';
  StockStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final all = store.stockList;
    final q = _query.trim().toLowerCase();
    final rows = all
        .where((s) => _filter == null || s.status == _filter)
        .where((s) => q.isEmpty || s.item.name.toLowerCase().contains(q) || s.item.id.toLowerCase().contains(q))
        .toList();
    int count(StockStatus st) => all.where((s) => s.status == st).length;
    final month = store.spentThisMonth, year = store.spentThisYear;
    final spendCols = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      appBar: AppBar(title: Text(tx('Stock', 'المخزون')), bottom: SubNav.bar(context)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => editItem(context, store, null),
        icon: const Icon(Icons.add),
        label: Text(tx('New item', 'مادة جديدة')),
      ),
      body: CardList(
        empty: tx('No items match.', 'لا توجد مواد مطابقة.'),
        header: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterChip(tx('All items', 'كل المواد'), all.length, _filter == null, () => setState(() => _filter = null)),
              _FilterChip(
                tx('Low', 'منخفض'),
                count(StockStatus.low),
                _filter == StockStatus.low,
                () => setState(() => _filter = StockStatus.low),
                color: Colors.orange,
              ),
              _FilterChip(
                tx('Out', 'نفد'),
                count(StockStatus.out),
                _filter == StockStatus.out,
                () => setState(() => _filter = StockStatus.out),
                color: Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SearchField(onChanged: (v) => setState(() => _query = v), hint: tx('Search by name or code', 'ابحث بالاسم أو الرمز')),
        ],
        itemCount: rows.isEmpty ? 0 : rows.length + 1,
        itemBuilder: (_, i) => i == 0
            ? _HeaderRow(phone: isPhone(context), spend: spendCols)
            : _StockRow(
                rows[i - 1],
                phone: isPhone(context),
                spend: spendCols,
                month: month[rows[i - 1].item.id] ?? 0,
                year: year[rows[i - 1].item.id] ?? 0,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ItemDetailScreen(store: store, itemId: rows[i - 1].item.id),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(this.label, this.n, this.selected, this.onTap, {this.color});
  final String label;
  final int n;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => ChoiceChip(
    selected: selected,
    onSelected: (_) => onTap(),
    label: Text(
      '$label  $n',
      style: TextStyle(fontWeight: FontWeight.w600, color: selected ? null : color),
    ),
  );
}

const _cols = [70.0, null, 110.0, 90.0, 80.0, 84.0, 90.0, 90.0];

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.phone, required this.spend});
  final bool phone, spend;
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).textTheme.labelLarge!.copyWith(color: Colors.grey.shade700);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          if (!phone)
            SizedBox(
              width: _cols[0],
              child: Text(tx('Code', 'الرمز'), style: s),
            ),
          Expanded(child: Text(tx('Item', 'المادة'), style: s)),
          if (!phone)
            SizedBox(
              width: _cols[2],
              child: Text(tx('Unit', 'الوحدة'), style: s),
            ),
          SizedBox(
            width: _cols[3],
            child: Text(tx('In stock', 'الموجود'), style: s, textAlign: TextAlign.end),
          ),
          if (!phone)
            SizedBox(
              width: _cols[4],
              child: Text(tx('Min', 'الحد الأدنى'), style: s, textAlign: TextAlign.end),
            ),
          if (spend)
            SizedBox(
              width: _cols[6],
              child: Text(tx('This month', 'صرف الشهر'), style: s, textAlign: TextAlign.end),
            ),
          if (spend)
            SizedBox(
              width: _cols[7],
              child: Text(tx('This year', 'صرف السنة'), style: s, textAlign: TextAlign.end),
            ),
          SizedBox(
            width: _cols[5],
            child: Text(tx('Status', 'الحالة'), style: s, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}

class _StockRow extends StatelessWidget {
  const _StockRow(this.s, {required this.onTap, required this.phone, required this.spend, this.month = 0, this.year = 0});
  final bool spend; // room for the spend columns
  final StockInfo s;
  final num month, year; // spent in the open month and since 1 January
  final bool phone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: [
          if (!phone)
            SizedBox(
              width: _cols[0],
              child: Text(s.item.id, style: const TextStyle(color: Colors.grey)),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: NameText(s.item.name, style: const TextStyle(fontSize: 16.5)),
                ),
                if (!spend && (phone || month != 0))
                  Text(
                      [
                        if (phone) '${s.item.id} · ${s.item.unit}',
                        if (month != 0) tx('spent ${fmtQty(month)} this month', 'صُرف ${fmtQty(month)} هذا الشهر'),
                      ].join(' · '),
                      style: const TextStyle(color: Colors.grey, fontSize: 12.5)),
              ],
            ),
          ),
          if (!phone) SizedBox(width: _cols[2], child: NameText(s.item.unit)),
          SizedBox(
            width: _cols[3],
            child: Text(
              fmtQty(s.qty),
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ),
          if (!phone)
            SizedBox(
              width: _cols[4],
              child: Text(fmtQty(s.item.minLevel), textAlign: TextAlign.end),
            ),
          if (spend)
            SizedBox(
              width: _cols[6],
              child: Text(month == 0 ? '·' : fmtQty(month), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          if (spend)
            SizedBox(
              width: _cols[7],
              child: Text(year == 0 ? '·' : fmtQty(year), textAlign: TextAlign.end, style: const TextStyle(color: Colors.grey)),
            ),
          SizedBox(
            width: _cols[5],
            child: Center(child: StatusChip(s.status)),
          ),
        ],
      ),
    ),
  );
}
