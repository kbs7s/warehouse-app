import 'package:flutter/material.dart';

import '../models.dart';
import '../shell.dart';
import '../store.dart';
import '../ui.dart';
import 'item_picker.dart';

/// List of purchases from suppliers, newest first.
class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final q = _q.trim().toLowerCase();
    final list = store.purchases.reversed.where((p) {
      if (q.isEmpty) return true;
      return '${p.no}' == q ||
          (p.supplier ?? '').toLowerCase().contains(q) ||
          p.lines.any((l) => (store.item(l.itemId)?.name ?? '').contains(q));
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Purchases'), bottom: SubNav.bar(context)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openPurchase(context, widget.store, null),
        icon: const Icon(Icons.add),
        label: const Text('New purchase'),
      ),
      body: CardList(
        empty: 'No purchases found.',
        header: [SearchField(onChanged: (v) => setState(() => _q = v), hint: 'Purchase number, supplier or item')],
        itemCount: list.length,
        itemBuilder: (_, i) {
          final p = list[i];
          return ListTile(
            leading: CircleAvatar(child: Text('${p.no}')),
            title: NameText(p.supplier ?? 'No supplier', style: const TextStyle(fontSize: 17)),
            subtitle: Text('${fmtDate(p.date)}  ·  ${p.lines.length} items'),
            trailing: Text(fmtMoney(p.total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            onTap: () => openPurchase(context, widget.store, p),
          );
        },
      ),
    );
  }
}

void openPurchase(BuildContext context, WarehouseStore store, Purchase? p) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => PurchaseEditor(store: store, existing: p),
    fullscreenDialog: true,
  ),
);

class _Line {
  _Line(PurchaseLine l)
    : itemId = l.itemId,
      note = l.note,
      qty = TextEditingController(text: l.qty == 0 ? '' : fmtQty(l.qty)),
      price = TextEditingController(text: l.unitPrice == null ? '' : fmtQty(l.unitPrice!)),
      total = TextEditingController(text: l.total == 0 ? '' : fmtQty(l.total));
  final String itemId;
  final String? note;
  final TextEditingController qty, price, total;
}

class PurchaseEditor extends StatefulWidget {
  const PurchaseEditor({super.key, required this.store, this.existing});
  final WarehouseStore store;
  final Purchase? existing;

  @override
  State<PurchaseEditor> createState() => _PurchaseEditorState();
}

class _PurchaseEditorState extends State<PurchaseEditor> {
  late final WarehouseStore store = widget.store;
  late final _no = TextEditingController(text: '${widget.existing?.no ?? store.nextPurchaseNo}');
  late String? _date = widget.existing == null ? todayIso() : widget.existing!.date;
  late final _supplier = TextEditingController(text: widget.existing?.supplier);
  late final _note = TextEditingController(text: widget.existing?.note);
  late final List<_Line> _lines = [for (final l in widget.existing?.lines ?? <PurchaseLine>[]) _Line(l)];

  Future<void> _addItem() async {
    final id = await pickItem(context, store, already: {for (final l in _lines) l.itemId});
    if (id != null) setState(() => _lines.add(_Line(PurchaseLine(itemId: id, qty: 0))));
  }

  // Typing quantity or unit price fills in the line total.
  void _recalc(_Line l) {
    final q = parseNum(l.qty.text), p = parseNum(l.price.text);
    if (q != null && p != null) l.total.text = fmtQty(q * p).replaceAll(',', '');
    setState(() {});
  }

  num get _grandTotal => _lines.fold<num>(0, (s, l) => s + (parseNum(l.total.text) ?? 0));

  Future<void> _save() async {
    final no = int.tryParse(_no.text.trim());
    if (no == null) return toast(context, 'Enter a purchase number.');
    if (no != widget.existing?.no && store.purchases.any((p) => p.no == no)) {
      return toast(context, 'Purchase number $no already exists.');
    }
    final lines = <PurchaseLine>[];
    for (final l in _lines) {
      final q = parseNum(l.qty.text);
      if (q == null || q <= 0) return toast(context, 'Enter a quantity for ${store.item(l.itemId)?.name}.');
      lines.add(
        PurchaseLine(
          itemId: l.itemId,
          qty: q,
          unitPrice: parseNum(l.price.text),
          total: parseNum(l.total.text) ?? 0,
          note: l.note,
        ),
      );
    }
    if (lines.isEmpty) return toast(context, 'Add at least one item.');
    String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    store.savePurchase(
      Purchase(no: no, date: _date, supplier: t(_supplier), note: t(_note), lines: lines),
      replacingNo: widget.existing?.no,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.existing == null ? 'New purchase' : 'Purchase #${widget.existing!.no}'),
      actions: [
        if (widget.existing != null)
          IconButton(
            tooltip: 'Delete purchase',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirm(
                context,
                'Delete purchase #${widget.existing!.no}?',
                'The items on it are taken back out of stock.',
              )) {
                store.deletePurchase(widget.existing!.no);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: FilledButton(onPressed: _save, child: const Text('Save')),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: 140,
              child: TextField(
                controller: _no,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Purchase #', border: OutlineInputBorder()),
              ),
            ),
            SizedBox(
              width: 200,
              child: InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime.tryParse(_date ?? '') ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (d != null) setState(() => _date = isoDate(d));
                },
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date', border: OutlineInputBorder()),
                  child: Text(fmtDate(_date)),
                ),
              ),
            ),
            SizedBox(
              width: 300,
              child: SuggestField(label: 'Supplier', controller: _supplier, options: store.suppliers),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _note,
          decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('Items', style: Theme.of(context).textTheme.titleLarge),
            Text('Total: ${fmtMoney(_grandTotal)}', style: Theme.of(context).textTheme.titleMedium),
            FilledButton.tonalIcon(onPressed: _addItem, icon: const Icon(Icons.add), label: const Text('Add item')),
          ],
        ),
        const SizedBox(height: 8),
        if (_lines.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Tap "Add item" to start.')),
          ),
        for (final (i, l) in _lines.indexed) _lineRow(i, l),
      ],
    ),
  );

  Widget _lineRow(int i, _Line l) {
    final item = store.item(l.itemId);
    Widget field(TextEditingController c, String label, double w, {VoidCallback? onChanged}) => SizedBox(
      width: w,
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: TextField(
          controller: c,
          onChanged: onChanged == null ? (_) => setState(() {}) : (_) => onChanged(),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.end,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
        ),
      ),
    );
    final phone = isPhone(context);
    final name = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NameText(item?.name ?? l.itemId, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
          Row(
            children: [
              Text('${l.itemId}  ·  '),
              NameText(item?.unit ?? ''),
              if (l.note != null) ...[const Text('  ·  '), Flexible(child: NameText(l.note!))],
            ],
          ),
        ],
      ),
    );
    final remove = IconButton(
      tooltip: 'Remove',
      icon: const Icon(Icons.close),
      onPressed: () => setState(() => _lines.removeAt(i)),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: phone
            ? Column(
                children: [
                  Row(children: [name, remove]),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: field(l.qty, 'Qty', double.infinity, onChanged: () => _recalc(l))),
                      Expanded(child: field(l.price, 'Unit price', double.infinity, onChanged: () => _recalc(l))),
                      Expanded(child: field(l.total, 'Total', double.infinity)),
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text('${i + 1}', style: const TextStyle(color: Colors.grey)),
                  ),
                  name,
                  field(l.qty, 'Qty', 100, onChanged: () => _recalc(l)),
                  field(l.price, 'Unit price', 130, onChanged: () => _recalc(l)),
                  field(l.total, 'Total (IQD)', 150),
                  remove,
                ],
              ),
      ),
    );
  }
}
