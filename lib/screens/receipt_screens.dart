import 'package:flutter/material.dart';

import '../models.dart';
import '../pdf.dart';
import '../store.dart';
import '../ui.dart';
import 'item_picker.dart';

/// List of issue receipts (items given to departments), newest first.
class ReceiptsScreen extends StatefulWidget {
  const ReceiptsScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  State<ReceiptsScreen> createState() => _ReceiptsScreenState();
}

class _ReceiptsScreenState extends State<ReceiptsScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final q = _q.trim().toLowerCase();
    final list = store.receipts.reversed.where((r) {
      if (q.isEmpty) return true;
      return '${r.no}' == q ||
          (r.department ?? '').toLowerCase().contains(q) ||
          (r.customer ?? '').toLowerCase().contains(q) ||
          r.lines.any((l) => (store.item(l.itemId)?.name ?? '').contains(q));
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Issue receipts')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openReceipt(context, store, null),
        icon: const Icon(Icons.add),
        label: const Text('New receipt'),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(children: [
          SearchField(onChanged: (v) => setState(() => _q = v), hint: 'Receipt number, department, person or item'),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = list[i];
                return ListTile(
                  leading: CircleAvatar(child: Text('${r.no}')),
                  title: Row(children: [
                    Flexible(child: NameText(r.department ?? 'No department', style: const TextStyle(fontSize: 17))),
                    if (r.customer != null) ...[const Text('  ·  '), Flexible(child: NameText(r.customer!))],
                  ]),
                  subtitle: Text('${fmtDate(r.date)}  ·  ${r.lines.length} items'),
                  trailing: IconButton(
                    tooltip: 'PDF',
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    onPressed: () => shareReceiptPdf(store, r),
                  ),
                  onTap: () => openReceipt(context, store, r),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}

void openReceipt(BuildContext context, WarehouseStore store, Receipt? r) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => ReceiptEditor(store: store, existing: r), fullscreenDialog: true));

class _Line {
  _Line(this.itemId, num? qty) : qty = TextEditingController(text: qty == null ? '' : fmtQty(qty));
  final String itemId;
  final TextEditingController qty;
}

class ReceiptEditor extends StatefulWidget {
  const ReceiptEditor({super.key, required this.store, this.existing});
  final WarehouseStore store;
  final Receipt? existing;

  @override
  State<ReceiptEditor> createState() => _ReceiptEditorState();
}

class _ReceiptEditorState extends State<ReceiptEditor> {
  late final WarehouseStore store = widget.store;
  late final _no = TextEditingController(text: '${widget.existing?.no ?? store.nextReceiptNo}');
  late String? _date = widget.existing?.date ?? todayIso();
  late final _dept = TextEditingController(text: widget.existing?.department);
  late final _person = TextEditingController(text: widget.existing?.customer);
  late final _note = TextEditingController(text: widget.existing?.note);
  late final List<_Line> _lines = [for (final l in widget.existing?.lines ?? <ReceiptLine>[]) _Line(l.itemId, l.qty)];

  @override
  void initState() {
    super.initState();
    _dept.addListener(() => setState(() {})); // refresh the "Received by" suggestions
  }

  /// Stock available for this receipt: current stock plus what this receipt already took (when editing).
  num _available(String itemId) {
    final before = widget.existing?.lines.where((l) => l.itemId == itemId).fold<num>(0, (s, l) => s + l.qty) ?? 0;
    return store.stock(itemId).qty + before;
  }

  Future<void> _addItem() async {
    final id = await pickItem(context, store, already: {for (final l in _lines) l.itemId});
    if (id != null) setState(() => _lines.add(_Line(id, null)));
  }

  Receipt? _build() {
    final no = int.tryParse(_no.text.trim());
    if (no == null) return _fail('Enter a receipt number.');
    if (no != widget.existing?.no && store.receipts.any((r) => r.no == no)) {
      return _fail('Receipt number $no already exists.');
    }
    if (_dept.text.trim().isEmpty) return _fail('Choose the department.');
    final lines = <ReceiptLine>[];
    for (final l in _lines) {
      final q = parseNum(l.qty.text);
      if (q == null || q <= 0) return _fail('Enter a quantity for ${store.item(l.itemId)?.name}.');
      lines.add(ReceiptLine(itemId: l.itemId, qty: q));
    }
    if (lines.isEmpty) return _fail('Add at least one item.');
    String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    return Receipt(no: no, date: _date, department: t(_dept), customer: t(_person), note: t(_note), lines: lines);
  }

  Null _fail(String msg) {
    toast(context, msg);
    return null;
  }

  Future<void> _save({bool pdf = false}) async {
    final r = _build();
    if (r == null) return;
    final over = r.lines.where((l) => l.qty > _available(l.itemId)).toList();
    if (over.isNotEmpty &&
        !await confirm(
            context,
            'Not enough stock',
            'These items would go below zero:\n\n${over.map((l) => '• ${store.item(l.itemId)?.name}: '
                'issuing ${fmtQty(l.qty)}, only ${fmtQty(_available(l.itemId))} in stock').join('\n')}\n\nSave anyway?',
            action: 'Save anyway')) {
      return;
    }
    store.saveReceipt(r, replacingNo: widget.existing?.no);
    if (!mounted) return;
    Navigator.pop(context);
    if (pdf) await shareReceiptPdf(store, r);
  }

  @override
  Widget build(BuildContext context) {
    final people = [
      for (final c in store.customers)
        if (_dept.text.trim().isEmpty || c.department == _dept.text.trim()) c.name
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'New issue receipt' : 'Receipt #${widget.existing!.no}'),
        actions: [
          if (widget.existing != null)
            IconButton(
              tooltip: 'Delete receipt',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, 'Delete receipt #${widget.existing!.no}?',
                    'The items on it go back into stock.')) {
                  store.deleteReceipt(widget.existing!.no);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
          TextButton(onPressed: () => _save(pdf: true), child: const Text('Save & PDF')),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(onPressed: _save, child: const Text('Save')),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Wrap(spacing: 16, runSpacing: 16, children: [
          SizedBox(
              width: 140,
              child: TextField(
                  controller: _no,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Receipt #', border: OutlineInputBorder()))),
          SizedBox(
            width: 200,
            child: InkWell(
              onTap: () async {
                final d = await showDatePicker(
                    context: context,
                    initialDate: DateTime.tryParse(_date ?? '') ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100));
                if (d != null) setState(() => _date = isoDate(d));
              },
              child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date', border: OutlineInputBorder()),
                  child: Text(fmtDate(_date))),
            ),
          ),
          SizedBox(
              width: 260,
              child: SuggestField(label: 'Department', controller: _dept, options: store.departments)),
          SizedBox(width: 260, child: SuggestField(label: 'Received by', controller: _person, options: people)),
        ]),
        const SizedBox(height: 16),
        TextField(
            controller: _note, decoration: const InputDecoration(labelText: 'Note', border: OutlineInputBorder())),
        const SizedBox(height: 24),
        Row(children: [
          Text('Items', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          FilledButton.tonalIcon(onPressed: _addItem, icon: const Icon(Icons.add), label: const Text('Add item')),
        ]),
        const SizedBox(height: 8),
        if (_lines.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('Tap "Add item" to start.'))),
        for (final (i, l) in _lines.indexed) _lineRow(i, l),
      ]),
    );
  }

  Widget _lineRow(int i, _Line l) {
    final item = store.item(l.itemId);
    final avail = _available(l.itemId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          SizedBox(width: 32, child: Text('${i + 1}', style: const TextStyle(color: Colors.grey))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              NameText(item?.name ?? l.itemId, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
              Text('${l.itemId}  ·  in stock: ${fmtQty(avail)}',
                  style: TextStyle(color: avail <= 0 ? Colors.red : Colors.grey.shade700)),
            ]),
          ),
          SizedBox(
            width: 120,
            child: TextField(
              controller: l.qty,
              autofocus: l.qty.text.isEmpty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.end,
              decoration: const InputDecoration(labelText: 'Qty', border: OutlineInputBorder(), isDense: true),
            ),
          ),
          SizedBox(width: 90, child: Padding(padding: const EdgeInsets.only(left: 8), child: NameText(item?.unit ?? ''))),
          IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() => _lines.removeAt(i))),
        ]),
      ),
    );
  }
}
