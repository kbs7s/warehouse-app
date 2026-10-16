import 'package:flutter/material.dart';

import '../models.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Stock'), bottom: SubNav.bar(context)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => editItem(context, store, null),
        icon: const Icon(Icons.add),
        label: const Text('New item'),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            _FilterChip('All items', all.length, _filter == null, () => setState(() => _filter = null)),
            _FilterChip('Low', count(StockStatus.low), _filter == StockStatus.low,
                () => setState(() => _filter = StockStatus.low), color: Colors.orange),
            _FilterChip('Out', count(StockStatus.out), _filter == StockStatus.out,
                () => setState(() => _filter = StockStatus.out), color: Colors.red),
          ]),
          const SizedBox(height: 12),
          SearchField(onChanged: (v) => setState(() => _query = v), hint: 'Search by name or code'),
          const SizedBox(height: 8),
          _HeaderRow(phone: isPhone(context)),
          Expanded(
            child: rows.isEmpty
                ? const Center(child: Text('No items match.'))
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 96),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) => _StockRow(rows[i], phone: isPhone(context), onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => ItemDetailScreen(store: store, itemId: rows[i].item.id)));
                    }),
                  ),
          ),
        ]),
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
        label: Text('$label  $n',
            style: TextStyle(fontWeight: FontWeight.w600, color: selected ? null : color)),
      );
}

const _cols = [70.0, null, 110.0, 90.0, 80.0, 84.0];

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.phone});
  final bool phone;
  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).textTheme.labelLarge!.copyWith(color: Colors.grey.shade700);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(children: [
        if (!phone) SizedBox(width: _cols[0], child: Text('Code', style: s)),
        Expanded(child: Text('Item', style: s)),
        if (!phone) SizedBox(width: _cols[2], child: Text('Unit', style: s)),
        SizedBox(width: _cols[3], child: Text('In stock', style: s, textAlign: TextAlign.end)),
        if (!phone) SizedBox(width: _cols[4], child: Text('Min', style: s, textAlign: TextAlign.end)),
        SizedBox(width: _cols[5], child: Text('Status', style: s, textAlign: TextAlign.center)),
      ]),
    );
  }
}

class _StockRow extends StatelessWidget {
  const _StockRow(this.s, {required this.onTap, required this.phone});
  final StockInfo s;
  final bool phone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(children: [
            if (!phone) SizedBox(width: _cols[0], child: Text(s.item.id, style: const TextStyle(color: Colors.grey))),
            Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: NameText(s.item.name, style: const TextStyle(fontSize: 16.5))),
              if (phone) Text('${s.item.id} · ${s.item.unit}', style: const TextStyle(color: Colors.grey, fontSize: 12.5)),
            ])),
            if (!phone) SizedBox(width: _cols[2], child: NameText(s.item.unit)),
            SizedBox(
                width: _cols[3],
                child: Text(fmtQty(s.qty),
                    textAlign: TextAlign.end, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
            if (!phone) SizedBox(width: _cols[4], child: Text(fmtQty(s.item.minLevel), textAlign: TextAlign.end)),
            SizedBox(width: _cols[5], child: Center(child: StatusChip(s.status))),
          ]),
        ),
      );
}
