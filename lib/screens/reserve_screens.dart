import 'package:flutter/material.dart';

import '../l10n.dart';
import '../shell.dart';
import '../store.dart';
import '../theme.dart';
import '../ui.dart';
import 'item_picker.dart';
import 'receipt_screens.dart';

/// The reserve store: the same items as the main store, kept apart for emergencies.
class ReserveScreen extends StatefulWidget {
  const ReserveScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  State<ReserveScreen> createState() => _ReserveScreenState();
}

class _ReserveScreenState extends State<ReserveScreen> {
  String _q = '';
  bool _inReserveOnly = true;

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final all = s.stockList;
    final held = all.where((x) => x.reserve != 0).length;
    final q = _q.trim().toLowerCase();
    final rows = all
        .where((x) => !_inReserveOnly || x.reserve != 0)
        .where((x) => q.isEmpty || x.item.name.toLowerCase().contains(q) || x.item.id.toLowerCase().contains(q))
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(tx('Reserve store', 'مخزن الاحتياط')), bottom: SubNav.bar(context)),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.bad,
        foregroundColor: Colors.white,
        onPressed: () => openReceipt(context, s, null, fromReserve: true),
        icon: const Icon(Icons.emergency_outlined),
        label: Text(tx('Emergency issue', 'صرف طارئ')),
      ),
      body: CardList(
        empty: _inReserveOnly
            ? tx('Nothing in the reserve store yet. Use "Move to reserve" to fill it.', 'لا توجد مواد في الاحتياط بعد. استخدم "نقل إلى الاحتياط" لملئه.')
            : tx('No items match.', 'لا توجد مواد مطابقة.'),
        header: [
          Wrap(spacing: 12, runSpacing: 8, children: [
            FilledButton.icon(
              onPressed: () => moveStock(context, s, toReserve: true),
              icon: const Icon(Icons.move_down),
              label: Text(tx('Move to reserve', 'نقل إلى الاحتياط')),
            ),
            OutlinedButton.icon(
              onPressed: () => moveStock(context, s, toReserve: false),
              icon: const Icon(Icons.move_up),
              label: Text(tx('Back to main store', 'إرجاع إلى المخزن الأساسي')),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: SearchField(onChanged: (v) => setState(() => _q = v), hint: tx('Search by name or code', 'ابحث بالاسم أو الرمز'))),
            const SizedBox(width: 12),
            FilterChip(
              label: Text(tx('In reserve ($held)', 'في الاحتياط ($held)')),
              selected: _inReserveOnly,
              onSelected: (v) => setState(() => _inReserveOnly = v),
            ),
          ]),
        ],
        itemCount: rows.length,
        itemBuilder: (_, i) {
          final x = rows[i];
          return ListTile(
            title: NameText(x.item.name, style: const TextStyle(fontSize: 16.5)),
            subtitle: Text('${x.item.id} · ${x.item.unit} · ${tx('main store', 'الأساسي')} ${fmtQty(x.qty)}'),
            trailing: Text(fmtQty(x.reserve),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: x.reserve < 0 ? AppColors.bad : null)),
            onTap: () => moveStock(context, s, itemId: x.item.id, toReserve: true),
          );
        },
      ),
    );
  }
}

/// Every move between the two stores, newest first.
class TransfersScreen extends StatelessWidget {
  const TransfersScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  Widget build(BuildContext context) {
    final list = [...store.transfers]..sort((a, b) => b.date.compareTo(a.date) != 0 ? b.date.compareTo(a.date) : b.no.compareTo(a.no));
    final emergencies = store.receipts.where((r) => r.fromReserve).toList().reversed.toList();
    return Scaffold(
      appBar: AppBar(title: Text(tx('Moves', 'النقل')), bottom: SubNav.bar(context)),
      body: PageBody(children: [
        SectionTitle(tx('Between the stores', 'بين المخزنين')),
        if (list.isEmpty)
          Padding(padding: const EdgeInsets.all(8), child: Text(tx('No moves yet.', 'لا توجد عمليات نقل بعد.')))
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final t in list)
                ListTile(
                  leading: Icon(t.toReserve ? Icons.move_down : Icons.move_up, color: t.toReserve ? AppColors.warn : AppColors.good),
                  title: NameText(store.item(t.itemId)?.name ?? t.itemId),
                  subtitle: Text('${fmtDate(t.date)} · ${t.toReserve ? tx('to reserve', 'إلى الاحتياط') : tx('back to main', 'إلى الأساسي')}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(fmtQty(t.qty), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    IconButton(
                      tooltip: tx('Delete', 'حذف'),
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await confirm(context, tx('Delete this move?', 'حذف عملية النقل؟'),
                            tx('The quantity goes back to where it was.', 'ستعود الكمية إلى مكانها.'))) {
                          store.deleteTransfer(t.no);
                        }
                      },
                    ),
                  ]),
                ),
            ]),
          ),
        SectionTitle(tx('Emergency issues', 'الصرف الطارئ')),
        if (emergencies.isEmpty)
          Padding(padding: const EdgeInsets.all(8), child: Text(tx('No emergency issues yet.', 'لا يوجد صرف طارئ بعد.')))
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final r in emergencies)
                ListTile(
                  leading: CircleAvatar(child: Text('${r.no}')),
                  title: NameText(r.department ?? '—'),
                  subtitle: Text(tx('${fmtDate(r.date)} · ${r.lines.length} items', '${fmtDate(r.date)} · ${r.lines.length} مادة')),
                  onTap: () => openReceipt(context, store, r),
                ),
            ]),
          ),
      ]),
    );
  }
}

/// Moves an item between the main and reserve stores.
Future<void> moveStock(BuildContext context, WarehouseStore store, {String? itemId, required bool toReserve}) =>
    showDialog(context: context, builder: (_) => _MoveDialog(store: store, itemId: itemId, toReserve: toReserve));

class _MoveDialog extends StatefulWidget {
  const _MoveDialog({required this.store, this.itemId, required this.toReserve});
  final WarehouseStore store;
  final String? itemId;
  final bool toReserve;

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  late String? _item = widget.itemId;
  late bool _toReserve = widget.toReserve;
  final _qty = TextEditingController();
  String _date = todayIso();

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final st = _item == null ? null : s.stock(_item!);
    final from = st == null ? 0 : (_toReserve ? st.qty : st.reserve);
    return AlertDialog(
      title: Text(tx('Move between stores', 'نقل بين المخزنين')),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: true, label: Text(tx('To reserve', 'إلى الاحتياط')), icon: const Icon(Icons.move_down)),
              ButtonSegment(value: false, label: Text(tx('Back to main', 'إلى الأساسي')), icon: const Icon(Icons.move_up)),
            ],
            selected: {_toReserve},
            onSelectionChanged: (v) => setState(() => _toReserve = v.first),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(alignment: AlignmentDirectional.centerStart, padding: const EdgeInsets.all(14)),
            onPressed: () async {
              final id = await pickItem(context, s);
              if (id != null) setState(() => _item = id);
            },
            icon: const Icon(Icons.inventory_2_outlined),
            label: _item == null ? Text(tx('Choose item', 'اختر المادة')) : NameText(s.item(_item!)?.name ?? _item!),
          ),
          if (st != null) ...[
            const SizedBox(height: 8),
            Text(tx('Main store ${fmtQty(st.qty)} · reserve ${fmtQty(st.reserve)}', 'الأساسي ${fmtQty(st.qty)} · الاحتياط ${fmtQty(st.reserve)}')),
          ],
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _qty,
                autofocus: widget.itemId != null,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tx('Quantity', 'الكمية'), border: const OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                      context: context, initialDate: DateTime.tryParse(_date) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                  if (d != null) setState(() => _date = isoDate(d));
                },
                child: InputDecorator(
                    decoration: InputDecoration(labelText: tx('Date', 'التاريخ'), border: const OutlineInputBorder()), child: Text(fmtDate(_date))),
              ),
            ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tx('Cancel', 'إلغاء'))),
        FilledButton(
          onPressed: () {
            final q = parseNum(_qty.text);
            if (_item == null) return toast(context, tx('Choose the item.', 'اختر المادة.'));
            if (q == null || q <= 0) return toast(context, tx('Enter the quantity.', 'أدخل الكمية.'));
            if (q > from) {
              return toast(context, tx('Only ${fmtQty(from)} there to move.', 'الموجود للنقل ${fmtQty(from)} فقط.'));
            }
            s.transfer(_item!, q, toReserve: _toReserve, date: _date);
            Navigator.pop(context);
          },
          child: Text(tx('Move', 'نقل')),
        ),
      ],
    );
  }
}
