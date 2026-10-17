import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';
import '../pdf.dart';
import '../shell.dart';
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
      appBar: AppBar(title: Text(tx('Issues to departments', 'الصرف إلى الأقسام')), bottom: SubNav.bar(context)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openReceipt(context, store, null),
        icon: const Icon(Icons.add),
        label: Text(tx('Issue supplies', 'صرف مواد')),
      ),
      body: CardList(
        empty: tx('No issue receipts found.', 'لا توجد وصولات صرف.'),
        header: [SearchField(onChanged: (v) => setState(() => _q = v), hint: tx('Receipt number, department, person or item', 'رقم الوصل أو القسم أو المستلم أو المادة'))],
        itemCount: list.length,
        itemBuilder: (_, i) {
          final r = list[i];
          return ListTile(
            leading: CircleAvatar(child: Text('${r.no}')),
            title: Row(
              children: [
                Flexible(child: NameText(r.department ?? tx('No department', 'بدون قسم'), style: const TextStyle(fontSize: 17))),
                if (r.customer != null) ...[const Text('  ·  '), Flexible(child: NameText(r.customer!))],
              ],
            ),
            subtitle: Text(tx('${fmtDate(r.date)}  ·  ${r.lines.length} items', '${fmtDate(r.date)}  ·  ${r.lines.length} مادة')),
            trailing: IconButton(
              tooltip: 'PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () => shareReceiptPdf(store, r),
            ),
            onTap: () => openReceipt(context, store, r),
          );
        },
      ),
    );
  }
}

void openReceipt(BuildContext context, WarehouseStore store, Receipt? r) => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => ReceiptEditor(store: store, existing: r),
    fullscreenDialog: true,
  ),
);

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

  /// The departments most recently issued to, for one-tap picking.
  late final List<String> _recentDepts = () {
    final seen = <String>{};
    for (final r in store.receipts.reversed) {
      final d = r.department?.trim() ?? '';
      if (d.isNotEmpty) seen.add(d);
      if (seen.length == 8) break;
    }
    return seen.toList();
  }();

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
    if (no == null) return _fail(tx('Enter a receipt number.', 'أدخل رقم الوصل.'));
    if (no != widget.existing?.no && store.receipts.any((r) => r.no == no)) {
      return _fail(tx('Receipt number $no already exists.', 'رقم الوصل $no موجود مسبقاً.'));
    }
    if (_dept.text.trim().isEmpty) return _fail(tx('Choose the department.', 'اختر القسم.'));
    final lines = <ReceiptLine>[];
    for (final l in _lines) {
      final q = parseNum(l.qty.text);
      if (q == null || q <= 0) return _fail(tx('Enter a quantity for ${store.item(l.itemId)?.name}.', 'أدخل الكمية لـ ${store.item(l.itemId)?.name}.'));
      lines.add(ReceiptLine(itemId: l.itemId, qty: q));
    }
    if (lines.isEmpty) return _fail(tx('Add at least one item.', 'أضف مادة واحدة على الأقل.'));
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
    String overLine(ReceiptLine l) {
      final q = fmtQty(l.qty), a = fmtQty(_available(l.itemId));
      return '• ${store.item(l.itemId)?.name}: ${tx('issuing $q, only $a in stock', 'صرف $q، والموجود $a فقط')}';
    }

    if (over.isNotEmpty &&
        !await confirm(
          context,
          tx('Not enough stock', 'المخزون غير كافٍ'),
          '${tx('These items would go below zero:', 'هذه المواد ستصبح دون الصفر:')}\n\n'
          '${over.map(overLine).join('\n')}\n\n'
          '${tx('Save anyway?', 'الحفظ على أي حال؟')}',
          action: tx('Save anyway', 'احفظ على أي حال'),
        )) {
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
        if (_dept.text.trim().isEmpty || c.department == _dept.text.trim()) c.name,
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null
            ? tx('New issue receipt', 'وصل صرف جديد')
            : tx('Receipt #${widget.existing!.no}', 'وصل رقم ${widget.existing!.no}')),
        actions: [
          if (widget.existing != null)
            IconButton(
              tooltip: tx('Delete receipt', 'حذف الوصل'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, tx('Delete receipt #${widget.existing!.no}?', 'حذف الوصل رقم ${widget.existing!.no}؟'),
                    tx('The items on it go back into stock.', 'ستعود مواده إلى المخزون.'))) {
                  store.deleteReceipt(widget.existing!.no);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
          TextButton(onPressed: () => _save(pdf: true), child: Text(tx('Save & PDF', 'حفظ و PDF'))),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(onPressed: _save, child: Text(tx('Save', 'حفظ'))),
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
                  decoration: InputDecoration(labelText: tx('Receipt #', 'رقم الوصل'), border: const OutlineInputBorder()),
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
                    decoration: InputDecoration(labelText: tx('Date', 'التاريخ'), border: const OutlineInputBorder()),
                    child: Text(fmtDate(_date)),
                  ),
                ),
              ),
              SizedBox(
                width: 260,
                child: SuggestField(label: tx('Department', 'القسم'), controller: _dept, options: store.departments),
              ),
              SizedBox(
                width: 260,
                child: SuggestField(label: tx('Received by', 'المستلم'), controller: _person, options: people),
              ),
            ],
          ),
          if (_dept.text.trim().isEmpty && _recentDepts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in _recentDepts)
                ActionChip(
                  avatar: const Icon(Icons.local_hospital_outlined, size: 18),
                  label: NameText(d),
                  onPressed: () => _dept.text = d,
                ),
            ]),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            decoration: InputDecoration(labelText: tx('Note', 'ملاحظة'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text(tx('Items', 'المواد'), style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              FilledButton.tonalIcon(onPressed: _addItem, icon: const Icon(Icons.add), label: Text(tx('Add item', 'إضافة مادة'))),
            ],
          ),
          const SizedBox(height: 8),
          if (_lines.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(tx('Tap "Add item" to start.', 'اضغط "إضافة مادة" للبدء.'))),
            ),
          for (final (i, l) in _lines.indexed) _lineRow(i, l),
        ],
      ),
    );
  }

  Widget _lineRow(int i, _Line l) {
    final item = store.item(l.itemId);
    final avail = _available(l.itemId);
    final phone = isPhone(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            if (!phone)
              SizedBox(
                width: 32,
                child: Text('${i + 1}', style: const TextStyle(color: Colors.grey)),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NameText(item?.name ?? l.itemId, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
                  Text(
                    tx('${l.itemId}  ·  in stock: ${fmtQty(avail)}', '${l.itemId}  ·  الموجود: ${fmtQty(avail)}'),
                    style: TextStyle(color: avail <= 0 ? Colors.red : Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: phone ? 84 : 120,
              child: TextField(
                controller: l.qty,
                autofocus: l.qty.text.isEmpty,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.end,
                decoration: InputDecoration(labelText: tx('Qty', 'الكمية'), border: const OutlineInputBorder(), isDense: true),
              ),
            ),
            SizedBox(
              width: phone ? 56 : 90,
              child: Padding(padding: const EdgeInsets.only(left: 8), child: NameText(item?.unit ?? '')),
            ),
            IconButton(tooltip: tx('Remove', 'إزالة'), icon: const Icon(Icons.close), onPressed: () => setState(() => _lines.removeAt(i))),
          ],
        ),
      ),
    );
  }
}
