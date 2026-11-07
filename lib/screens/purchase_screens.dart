import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';
import '../shell.dart';
import '../store.dart';
import '../theme.dart';
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
  bool _owedOnly = false;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final q = _q.trim().toLowerCase();
    final list = store.purchases.reversed.where((p) {
      if (_owedOnly && p.owed <= 0) return false;
      if (q.isEmpty) return true;
      return '${p.no}' == q ||
          (p.ref ?? '').toLowerCase() == q ||
          (p.supplier ?? '').toLowerCase().contains(q) ||
          p.lines.any((l) => (store.item(l.itemId)?.name ?? '').contains(q));
    }).toList();
    final (from, to) = Period.thisMonth.range();
    final thisMonth = store.purchases.where((p) => (p.date ?? '').compareTo(from) >= 0 && (p.date ?? '').compareTo(to) <= 0);
    final unpaid = store.purchases.where((p) => p.owed > 0).length;

    return Scaffold(
      appBar: AppBar(title: Text(tx('Purchases', 'المشتريات')), bottom: SubNav.bar(context)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openPurchase(context, widget.store, null),
        icon: const Icon(Icons.add),
        label: Text(tx('New purchase', 'شراء جديد')),
      ),
      body: CardList(
        empty: _owedOnly ? tx('Every purchase is paid.', 'كل المشتريات مسددة.') : tx('No purchases found.', 'لا توجد مشتريات.'),
        header: [
          TileGrid(wideColumns: 3, children: [
            MetricTile(
                label: tx('Still owed to suppliers', 'المتبقي للمجهزين'),
                value: fmtMoneyShort(store.weOwe),
                icon: Icons.hourglass_bottom,
                color: store.weOwe > 0 ? AppColors.bad : AppColors.good,
                hint: tx('$unpaid purchases not fully paid', '$unpaid قوائم غير مسددة بالكامل'),
                onTap: () => setState(() => _owedOnly = true)),
            MetricTile(
                label: tx('Bought this month', 'مشتريات هذا الشهر'),
                value: fmtMoneyShort(thisMonth.fold<num>(0, (s, p) => s + p.total)),
                icon: Icons.shopping_cart_outlined,
                hint: tx('${thisMonth.length} purchases', '${thisMonth.length} قوائم')),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: SearchField(
                    onChanged: (v) => setState(() => _q = v),
                    hint: tx('Purchase number, supplier or item', 'رقم الشراء أو المجهز أو المادة'))),
            const SizedBox(width: 12),
            FilterChip(
                label: Text(tx('Not paid', 'غير مسددة')),
                selected: _owedOnly,
                onSelected: (v) => setState(() => _owedOnly = v)),
          ]),
        ],
        itemCount: list.length,
        itemBuilder: (_, i) {
          final p = list[i];
          return ListTile(
            leading: CircleAvatar(child: Text('${p.no}')),
            title: NameText(p.supplier ?? tx('No supplier', 'بدون مجهز'), style: const TextStyle(fontSize: 17)),
            subtitle: Text([
              fmtDate(p.date),
              tx('${p.lines.length} items', '${p.lines.length} مادة'),
              if (p.ref != null) tx('bill ${p.ref}', 'قائمة ${p.ref}'),
            ].join('  ·  ')),
            trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(fmtMoney(p.total), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              if (p.tracked) PayStatus(p),
            ]),
            onTap: () => openPurchase(context, widget.store, p),
          );
        },
      ),
    );
  }
}

/// "Paid" in green or "Owed 25,000 IQD" in red, for a purchase whose payment is tracked.
class PayStatus extends StatelessWidget {
  const PayStatus(this.p, {super.key});
  final Purchase p;

  @override
  Widget build(BuildContext context) => Text(
        p.settled
            ? tx('Paid', 'مسددة')
            : p.paid > 0
                ? tx('Owed ${fmtMoney(p.owed)}', 'متبقي ${fmtMoney(p.owed)}')
                : tx('Not paid', 'غير مسددة'),
        style: TextStyle(color: p.settled ? AppColors.good : AppColors.bad, fontWeight: FontWeight.w600),
      );
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
      total = TextEditingController(text: l.total == 0 ? '' : fmtQty(l.total)),
      expiry = l.expiry,
      lot = TextEditingController(text: l.lot);
  final String itemId;
  final String? note;
  final TextEditingController qty, price, total, lot;
  String? expiry;
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
  late final _ref = TextEditingController(text: widget.existing?.ref);
  // New purchases start unpaid; older ones keep "not recorded" until a payment is added.
  late List<PurchasePaid>? _paidLog = widget.existing == null
      ? []
      : widget.existing!.paidLog == null
          ? null
          : [for (final p in widget.existing!.paidLog!) PurchasePaid(amount: p.amount, date: p.date, note: p.note)];
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
    if (no == null) return toast(context, tx('Enter a purchase number.', 'أدخل رقم الشراء.'));
    if (no != widget.existing?.no && store.purchases.any((p) => p.no == no)) {
      return toast(context, tx('Purchase number $no already exists.', 'رقم الشراء $no موجود مسبقاً.'));
    }
    final lines = <PurchaseLine>[];
    for (final l in _lines) {
      final q = parseNum(l.qty.text);
      if (q == null || q <= 0) return toast(context, tx('Enter a quantity for ${store.item(l.itemId)?.name}.', 'أدخل الكمية لـ ${store.item(l.itemId)?.name}.'));
      lines.add(
        PurchaseLine(
          itemId: l.itemId,
          qty: q,
          unitPrice: parseNum(l.price.text),
          total: parseNum(l.total.text) ?? 0,
          note: l.note,
          expiry: l.expiry,
          lot: l.lot.text.trim().isEmpty ? null : l.lot.text.trim(),
        ),
      );
    }
    if (lines.isEmpty) return toast(context, tx('Add at least one item.', 'أضف مادة واحدة على الأقل.'));
    String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    store.savePurchase(
      Purchase(no: no, date: _date, supplier: t(_supplier), note: t(_note), ref: t(_ref), lines: lines, paidLog: _paidLog),
      replacingNo: widget.existing?.no,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.existing == null
          ? tx('New purchase', 'شراء جديد')
          : tx('Purchase #${widget.existing!.no}', 'شراء رقم ${widget.existing!.no}')),
      actions: [
        if (widget.existing != null)
          IconButton(
            tooltip: tx('Delete purchase', 'حذف الشراء'),
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirm(
                context,
                tx('Delete purchase #${widget.existing!.no}?', 'حذف الشراء رقم ${widget.existing!.no}؟'),
                tx('The items on it are taken back out of stock.', 'ستُخرج مواده من المخزون.'),
              )) {
                store.deletePurchase(widget.existing!.no);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
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
                decoration: InputDecoration(labelText: tx('Purchase #', 'رقم الشراء'), border: const OutlineInputBorder()),
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
              width: 300,
              child: SuggestField(label: tx('Supplier', 'المجهز'), controller: _supplier, options: store.suppliers),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 16, runSpacing: 16, children: [
          SizedBox(
            width: 200,
            child: TextField(
              controller: _ref,
              decoration: InputDecoration(labelText: tx("Supplier's bill no.", 'رقم قائمة المجهز'), border: const OutlineInputBorder()),
            ),
          ),
          SizedBox(
            width: 456,
            child: TextField(
              controller: _note,
              decoration: InputDecoration(labelText: tx('Note', 'ملاحظة'), border: const OutlineInputBorder()),
            ),
          ),
        ]),
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(tx('Items', 'المواد'), style: Theme.of(context).textTheme.titleLarge),
            Text(tx('Total: ${fmtMoney(_grandTotal)}', 'المجموع: ${fmtMoney(_grandTotal)}'), style: Theme.of(context).textTheme.titleMedium),
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
        const SizedBox(height: 16),
        _paymentCard(),
      ],
    ),
  );

  num get _paid => (_paidLog ?? const []).fold<num>(0, (s, p) => s + p.amount);

  Widget _paymentCard() {
    final t = Theme.of(context);
    final owed = _grandTotal - _paid;
    final log = _paidLog;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tx('Payment', 'التسديد'), style: t.textTheme.titleLarge),
          const SizedBox(height: 8),
          if (log == null)
            Text(tx('Payment was not recorded for this older purchase.', 'لم يُسجَّل تسديد هذه القائمة السابقة.'))
          else ...[
            Wrap(spacing: 24, runSpacing: 8, children: [
              _money(tx('Total', 'المجموع'), _grandTotal),
              _money(tx('Paid', 'المدفوع'), _paid, color: AppColors.good),
              _money(tx('Still owed', 'المتبقي'), owed > 0 ? owed : 0, color: owed > 0 ? AppColors.bad : null),
            ]),
            for (final (i, p) in log.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.payments_outlined, color: AppColors.good),
                title: Text(fmtMoney(p.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text([fmtDate(p.date), if (p.note != null) p.note!].join('  ·  ')),
                trailing: IconButton(
                  tooltip: tx('Remove payment', 'حذف الدفعة'),
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => log.removeAt(i)),
                ),
              ),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 8, children: [
            if (log == null || owed > 0)
              FilledButton.tonalIcon(
                onPressed: () => setState(() {
                  final rest = _grandTotal - _paid;
                  _paidLog = [...?log, if (rest > 0) PurchasePaid(amount: rest, date: todayIso())];
                }),
                icon: const Icon(Icons.done_all),
                label: Text(tx('Paid in full', 'مدفوعة بالكامل')),
              ),
            OutlinedButton.icon(
              onPressed: () async {
                final p = await askPayment(context, owed: owed > 0 ? owed : null);
                if (p != null) setState(() => _paidLog = [...?log, p]);
              },
              icon: const Icon(Icons.add),
              label: Text(tx('Add payment', 'إضافة دفعة')),
            ),
            if (log == null)
              TextButton(onPressed: () => setState(() => _paidLog = []), child: Text(tx('Mark as not paid', 'غير مسددة'))),
          ]),
        ]),
      ),
    );
  }

  Widget _money(String label, num v, {Color? color}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text(fmtMoney(v), style: Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700, color: color)),
      ]);

  Widget _expiryRow(_Line l) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(alignment: AlignmentDirectional.centerStart),
              onPressed: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: DateTime.tryParse(l.expiry ?? '') ?? DateTime(now.year + 1, now.month, now.day),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                  helpText: tx('Expiry date', 'تاريخ الانتهاء'),
                );
                if (d != null) setState(() => l.expiry = isoDate(d));
              },
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(l.expiry == null ? tx('Expiry date', 'تاريخ الانتهاء') : tx('Expires ${fmtDate(l.expiry)}', 'تنتهي ${fmtDate(l.expiry)}')),
            ),
          ),
          if (l.expiry != null)
            IconButton(
              tooltip: tx('Clear expiry date', 'مسح تاريخ الانتهاء'),
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => l.expiry = null),
            ),
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: TextField(
              controller: l.lot,
              decoration: InputDecoration(labelText: tx('Batch / lot', 'رقم الوجبة'), border: const OutlineInputBorder(), isDense: true),
            ),
          ),
        ]),
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
      tooltip: tx('Remove', 'إزالة'),
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
                      Expanded(child: field(l.qty, tx('Qty', 'الكمية'), double.infinity, onChanged: () => _recalc(l))),
                      Expanded(child: field(l.price, tx('Unit price', 'سعر الوحدة'), double.infinity, onChanged: () => _recalc(l))),
                      Expanded(child: field(l.total, tx('Total', 'المجموع'), double.infinity)),
                    ],
                  ),
                  _expiryRow(l),
                ],
              )
            : Column(children: [
              Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text('${i + 1}', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ),
                  name,
                  field(l.qty, tx('Qty', 'الكمية'), 100, onChanged: () => _recalc(l)),
                  field(l.price, tx('Unit price', 'سعر الوحدة'), 130, onChanged: () => _recalc(l)),
                  field(l.total, tx('Total (IQD)', 'المجموع (د.ع)'), 150),
                  remove,
                ],
              ),
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 32, end: 48),
                child: _expiryRow(l),
              ),
            ]),
      ),
    );
  }
}

/// Asks how much was paid, when, and an optional note.
Future<PurchasePaid?> askPayment(BuildContext context, {num? owed}) =>
    showDialog<PurchasePaid>(context: context, builder: (_) => _PaymentDialog(owed: owed));

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({this.owed});
  final num? owed;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _date = todayIso();

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tx('Add payment', 'إضافة دفعة')),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (widget.owed != null) Text(tx('Still owed: ${fmtMoney(widget.owed!)}', 'المتبقي: ${fmtMoney(widget.owed!)}')),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tx('Amount paid (IQD)', 'المبلغ المدفوع (د.ع)'), border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                    context: context, initialDate: DateTime.tryParse(_date) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                if (d != null) setState(() => _date = isoDate(d));
              },
              child: InputDecorator(
                  decoration: InputDecoration(labelText: tx('Date', 'التاريخ'), border: const OutlineInputBorder()), child: Text(fmtDate(_date))),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration: InputDecoration(labelText: tx('Note (optional)', 'ملاحظة (اختياري)'), border: const OutlineInputBorder()),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tx('Cancel', 'إلغاء'))),
          FilledButton(
            onPressed: () {
              final a = parseNum(_amount.text);
              if (a == null || a <= 0) return toast(context, tx('Enter the amount paid.', 'أدخل المبلغ المدفوع.'));
              final n = _note.text.trim();
              Navigator.pop(context, PurchasePaid(amount: a, date: _date, note: n.isEmpty ? null : n));
            },
            child: Text(tx('Add', 'إضافة')),
          ),
        ],
      );
}
