import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';
import '../shell.dart';
import '../store.dart';
import '../theme.dart';
import '../ui.dart';
import 'item_picker.dart';
import 'receipt_screens.dart';

/// Requests from departments. A department login sees and writes its own; the store sees all of
/// them and turns each into an issue receipt.
class RequestsScreen extends StatefulWidget {
  const RequestsScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  State<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends State<RequestsScreen> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final dept = store.cloud?.isDept ?? false;
    final mine = store.cloud?.department ?? '';
    final list = [
      for (final r in store.requests.reversed)
        if ((!dept || r.department == mine) && (_all || dept || r.open)) r,
    ];
    final done = store.requests.where((r) => !r.open).length;
    return Scaffold(
      appBar: HeaderBar(title: Text(dept ? tx('My requests', 'طلباتي') : tx('Department requests', 'طلبات الأقسام')), bottom: SubNav.bar(context)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openRequest(context, store, null),
        icon: const Icon(Icons.add),
        label: Text(tx('New request', 'طلب جديد')),
      ),
      body: CardList(
        empty: dept
            ? tx('No requests yet. Tap "New request" to ask the store for supplies.', 'لا توجد طلبات بعد. اضغط "طلب جديد" لطلب مواد من المخزن.')
            : tx('No requests waiting.', 'لا توجد طلبات بانتظارك.'),
        header: [
          if (!dept && done > 0)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilterChip(
                label: Text(tx('Show answered too ($done)', 'عرض المُجابة أيضاً ($done)')),
                selected: _all,
                onSelected: (v) => setState(() => _all = v),
              ),
            ),
        ],
        itemCount: list.length,
        itemBuilder: (_, i) {
          final r = list[i];
          return ListTile(
            leading: CircleAvatar(child: Text('${r.no}')),
            title: NameText(r.department ?? tx('No department', 'بدون قسم'), style: const TextStyle(fontSize: 17)),
            subtitle: Text('${fmtDate(r.date)}  ·  ${r.lines.length} ${r.lines.length == 1 ? tx('item', 'مادة') : tx('items', 'مواد')}'
                '${r.by == null ? '' : '  ·  ${r.by}'}'),
            trailing: RequestStatus(r),
            onTap: () => openRequest(context, store, r),
          );
        },
      ),
    );
  }
}

class RequestStatus extends StatelessWidget {
  const RequestStatus(this.r, {super.key});
  final StoreRequest r;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (r.status) {
      'done' => (tx('Issued · receipt #${r.receiptNo}', 'صُرف · وصل ${r.receiptNo}'), scheme.good),
      'rejected' => (tx('Not issued', 'لم يُصرف'), scheme.bad),
      _ => (tx('Waiting', 'بانتظار المخزن'), scheme.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
    );
  }
}

void openRequest(BuildContext context, WarehouseStore store, StoreRequest? r) => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RequestEditor(store: store, existing: r), fullscreenDialog: true),
    );

class _Line {
  _Line(this.itemId, num? qty) : qty = TextEditingController(text: qty == null ? '' : fmtQty(qty));
  final String itemId;
  final TextEditingController qty;
}

/// A new request, or one already sent: the department edits it while it waits, the store answers it.
class RequestEditor extends StatefulWidget {
  const RequestEditor({super.key, required this.store, this.existing});
  final WarehouseStore store;
  final StoreRequest? existing;

  @override
  State<RequestEditor> createState() => _RequestEditorState();
}

class _RequestEditorState extends State<RequestEditor> {
  late final WarehouseStore store = widget.store;
  late final bool _dept = store.cloud?.isDept ?? false;
  late String? _department = widget.existing?.department ?? (_dept ? store.cloud!.department : null);
  late final _note = TextEditingController(text: widget.existing?.note);
  late final List<_Line> _lines = [for (final l in widget.existing?.lines ?? <ReceiptLine>[]) _Line(l.itemId, l.qty)];

  bool get _editable => widget.existing?.open ?? true;

  Future<void> _addItem() async {
    final id = await pickItem(context, store, already: {for (final l in _lines) l.itemId}, all: true);
    if (id != null) setState(() => _lines.add(_Line(id, null)));
  }

  StoreRequest? _build() {
    if ((_department ?? '').isEmpty) return _fail(tx('Choose the department.', 'اختر القسم.'));
    final lines = <ReceiptLine>[];
    for (final l in _lines) {
      final q = parseNum(l.qty.text);
      if (q == null || q <= 0) return _fail(tx('Enter a quantity for ${store.item(l.itemId)?.name}.', 'أدخل الكمية لـ ${store.item(l.itemId)?.name}.'));
      lines.add(ReceiptLine(itemId: l.itemId, qty: q));
    }
    if (lines.isEmpty) return _fail(tx('Add at least one item.', 'أضف مادة واحدة على الأقل.'));
    final ex = widget.existing;
    return StoreRequest(
      no: ex?.no ?? store.nextRequestNo,
      date: ex?.date ?? todayIso(),
      department: _department,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      lines: lines,
      by: ex?.by,
      at: ex?.at,
    );
  }

  Null _fail(String msg) {
    toast(context, msg);
    return null;
  }

  void _send() {
    final r = _build();
    if (r == null) return;
    store.saveRequest(r);
    Navigator.pop(context);
    toast(context, tx('Request #${r.no} sent to the store.', 'أُرسل الطلب رقم ${r.no} إلى المخزن.'));
  }

  /// The store answers: an issue receipt opens with the request's department and items filled in.
  Future<void> _issue() async {
    final r = _build();
    if (r == null) return;
    store.saveRequest(r);
    final nav = Navigator.of(context);
    await nav.push(MaterialPageRoute(builder: (_) => ReceiptEditor(store: store, request: r), fullscreenDialog: true));
    if (nav.mounted && !(store.requests.where((x) => x.no == r.no).firstOrNull?.open ?? false)) nav.pop();
  }

  Future<void> _reject() async {
    final r = widget.existing!;
    if (!await confirm(context, tx('Do not issue request #${r.no}?', 'عدم صرف الطلب رقم ${r.no}؟'),
        tx('The department sees it as "Not issued".', 'سيراه القسم بحالة "لم يُصرف".'), action: tx('Do not issue', 'عدم الصرف'))) {
      return;
    }
    store.closeRequest(r.no);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final ex = widget.existing;
    final t = Theme.of(context);
    return Scaffold(
      appBar: HeaderBar(
        title: Text(ex == null ? tx('New request', 'طلب جديد') : tx('Request #${ex.no}', 'طلب رقم ${ex.no}')),
        actions: [
          if (ex != null && _editable && (_dept || !(store.cloud?.isStaff ?? false)))
            IconButton(
              tooltip: tx('Delete request', 'حذف الطلب'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(context, tx('Delete request #${ex.no}?', 'حذف الطلب رقم ${ex.no}؟'), tx('The store will no longer see it.', 'لن يراه المخزن بعد الآن.'))) {
                  store.deleteRequest(ex.no);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
          if (_editable && !_dept && ex != null) TextButton(onPressed: _reject, child: Text(tx('Do not issue', 'عدم الصرف'))),
          if (_editable)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 12),
              child: _dept || ex == null
                  ? FilledButton(onPressed: _send, child: Text(ex == null ? tx('Send', 'إرسال') : tx('Save', 'حفظ')))
                  : FilledButton.icon(onPressed: _issue, icon: const Icon(Icons.outbox), label: Text(tx('Issue it', 'صرف الطلب'))),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (ex != null) ...[
            Row(children: [
              RequestStatus(ex),
              const SizedBox(width: 12),
              Expanded(child: Text('${fmtDate(ex.date)}${ex.by == null ? '' : '  ·  ${ex.by}'}', style: TextStyle(color: t.colorScheme.onSurfaceVariant))),
            ]),
            const SizedBox(height: 16),
          ],
          Text(tx('Department', 'القسم'), style: t.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_dept || !_editable)
            NameText(_department ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in {...store.departments, if ((_department ?? '').isNotEmpty) _department!})
                ChoiceChip(
                  avatar: const Icon(Icons.local_hospital_outlined, size: 18),
                  label: NameText(d),
                  selected: _department == d,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _department = d),
                ),
            ]),
          const SizedBox(height: 24),
          Row(children: [
            Text(tx('Items', 'المواد'), style: t.textTheme.titleLarge),
            const Spacer(),
            if (_editable) FilledButton.tonalIcon(onPressed: _addItem, icon: const Icon(Icons.add), label: Text(tx('Add item', 'إضافة مادة'))),
          ]),
          const SizedBox(height: 8),
          if (_lines.isEmpty)
            Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(tx('Tap "Add item" to start.', 'اضغط "إضافة مادة" للبدء.')))),
          for (final (i, l) in _lines.indexed) _lineRow(i, l),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            enabled: _editable,
            maxLines: 2,
            decoration: InputDecoration(labelText: tx('Note for the store (optional)', 'ملاحظة للمخزن (اختياري)'), border: const OutlineInputBorder()),
          ),
        ],
      ),
    );
  }

  Widget _lineRow(int i, _Line l) {
    final item = store.item(l.itemId);
    final ex = widget.existing;
    final given = ex?.given?.where((g) => g.itemId == l.itemId).fold<num>(0, (s, g) => s + g.qty);
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              NameText(item?.name ?? l.itemId, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500)),
              if (!_dept && _editable)
                Text(tx('in stock: ${fmtQty(store.stock(l.itemId).qty)}', 'الموجود: ${fmtQty(store.stock(l.itemId).qty)}'),
                    style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
              if (ex != null && ex.status == 'done')
                Text(tx('asked ${l.qty.text} · given ${fmtQty(given ?? 0)}', 'المطلوب ${l.qty.text} · المصروف ${fmtQty(given ?? 0)}'),
                    style: TextStyle(color: (given ?? 0) < (parseNum(l.qty.text) ?? 0) ? t.colorScheme.warning : t.colorScheme.good, fontWeight: FontWeight.w600)),
            ]),
          ),
          SizedBox(
            width: isPhone(context) ? 84 : 120,
            child: TextField(
              controller: l.qty,
              enabled: _editable,
              autofocus: l.qty.text.isEmpty,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.end,
              decoration: InputDecoration(labelText: tx('Qty', 'الكمية'), border: const OutlineInputBorder(), isDense: true),
            ),
          ),
          SizedBox(width: isPhone(context) ? 56 : 90, child: Padding(padding: const EdgeInsetsDirectional.only(start: 8), child: NameText(item?.unit ?? ''))),
          if (_editable) IconButton(tooltip: tx('Remove', 'إزالة'), icon: const Icon(Icons.close), onPressed: () => setState(() => _lines.removeAt(i))),
        ]),
      ),
    );
  }
}
