import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';
import '../pdf.dart';
import '../shell.dart';
import '../store.dart';
import '../theme.dart';
import '../ui.dart';
import 'client_screens.dart';
import 'item_picker.dart';

/// Opens an invoice: a new one goes straight to the editor, an existing one to its detail page.
Future<void> openInvoice(BuildContext context, WarehouseStore store, Invoice? inv, {String? clientId}) =>
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: inv == null,
      builder: (_) => inv == null
          ? InvoiceEditor(store: store, clientId: clientId)
          : ListenableBuilder(listenable: store, builder: (_, _) => InvoiceDetail(store: store, no: inv.no)),
    ));

class InvoiceStatusChip extends StatelessWidget {
  const InvoiceStatusChip(this.status, {super.key});
  final InvoiceStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      InvoiceStatus.paid => (tx('Paid', 'مدفوعة'), AppColors.good),
      InvoiceStatus.partlyPaid => (tx('Part paid', 'مدفوعة جزئياً'), AppColors.info),
      InvoiceStatus.unpaid => (tx('Unpaid', 'غير مدفوعة'), AppColors.warn),
      InvoiceStatus.overdue => (tx('Overdue', 'متأخرة'), AppColors.bad),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: .13), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
    );
  }
}

/// Payment methods are stored in English; show them in the interface language.
String payMethodLabel(String m) => switch (m) {
      'Cash' => tx('Cash', 'نقداً'),
      'Bank transfer' => tx('Bank transfer', 'تحويل مصرفي'),
      'Card' => tx('Card', 'بطاقة'),
      'Cheque' => tx('Cheque', 'صك'),
      _ => m,
    };

enum _Filter { all, open, overdue, paid }

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  String _q = '';
  _Filter _filter = _Filter.all;

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final today = todayIso();
    final q = _q.trim().toLowerCase();
    bool match(Invoice i) => switch (_filter) {
          _Filter.all => true,
          _Filter.open => i.balance > 0,
          _Filter.overdue => i.status(today) == InvoiceStatus.overdue,
          _Filter.paid => i.status(today) == InvoiceStatus.paid,
        };
    final list = s.invoices.reversed
        .where(match)
        .where((i) => q.isEmpty || '${i.no}' == q || (s.client(i.clientId)?.name.toLowerCase().contains(q) ?? false))
        .toList();
    final overdue = s.overdue(today);

    return Scaffold(
      appBar: AppBar(title: Text(tx('Invoices', 'الفواتير')), bottom: SubNav.bar(context)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openInvoice(context, s, null),
        icon: const Icon(Icons.add),
        label: Text(tx('New invoice', 'فاتورة جديدة')),
      ),
      body: PageBody(children: [
        TileGrid(wideColumns: 3, children: [
          MetricTile(label: tx('Clients owe you', 'ديونك على الزبائن'), value: fmtMoneyShort(s.owedToUs), icon: Icons.hourglass_bottom,
              hint: tx('${s.invoices.where((i) => i.balance > 0).length} invoices not fully paid',
                  '${s.invoices.where((i) => i.balance > 0).length} فواتير غير مسددة بالكامل')),
          MetricTile(
              label: tx('Overdue', 'متأخرة'),
              value: fmtMoneyShort(overdue.fold<num>(0, (t, i) => t + i.balance)),
              icon: Icons.error_outline,
              color: overdue.isEmpty ? null : AppColors.bad,
              hint: tx('${overdue.length} past the due date', '${overdue.length} تجاوزت تاريخ الاستحقاق')),
          MetricTile(
              label: tx('Collected this month', 'المحصّل هذا الشهر'),
              value: fmtMoneyShort(s.profit(Period.thisMonth.range().$1, Period.thisMonth.range().$2).received),
              icon: Icons.payments_outlined,
              color: AppColors.good),
        ]),
        const SizedBox(height: 16),
        SearchField(onChanged: (v) => setState(() => _q = v), hint: tx('Invoice number or client', 'رقم الفاتورة أو الزبون')),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in _Filter.values)
            ChoiceChip(
              showCheckmark: false,
              selected: _filter == f,
              onSelected: (_) => setState(() => _filter = f),
              label: Text(switch (f) {
                _Filter.all => tx('All', 'الكل'),
                _Filter.open => tx('Not paid', 'غير مسددة'),
                _Filter.overdue => tx('Overdue', 'متأخرة'),
                _Filter.paid => tx('Paid', 'مدفوعة'),
              }),
            ),
        ]),
        const SizedBox(height: 12),
        if (list.isEmpty)
          EmptyState(
            icon: Icons.receipt_long_outlined,
            title: s.invoices.isEmpty ? tx('No invoices yet', 'لا توجد فواتير بعد') : tx('No invoices match', 'لا توجد فاتورة مطابقة'),
            message: s.invoices.isEmpty
                ? tx('Create an invoice when you sell to a client. Stock items come out of stock automatically.',
                    'أنشئ فاتورة عندما تبيع لزبون. المواد تُخصم من المخزون تلقائياً.')
                : null,
            action: s.invoices.isEmpty
                ? FilledButton.icon(
                    onPressed: () => openInvoice(context, s, null), icon: const Icon(Icons.add), label: Text(tx('New invoice', 'فاتورة جديدة')))
                : null,
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final (i, inv) in list.indexed) ...[
                if (i > 0) const Divider(height: 1),
                InvoiceTile(store: s, inv: inv),
              ],
            ]),
          ),
      ]),
    );
  }
}

class InvoiceTile extends StatelessWidget {
  const InvoiceTile({super.key, required this.store, required this.inv, this.showClient = true});
  final WarehouseStore store;
  final Invoice inv;
  final bool showClient;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final client = store.client(inv.clientId)?.name ?? tx('No client', 'بدون زبون');
    return ListTile(
      onTap: () => openInvoice(context, store, inv),
      leading: CircleAvatar(
        backgroundColor: t.colorScheme.primaryContainer,
        child: Text('${inv.no}', style: TextStyle(fontSize: 13, color: t.colorScheme.onPrimaryContainer, fontWeight: FontWeight.w700)),
      ),
      title: showClient ? NameText(client, style: const TextStyle(fontWeight: FontWeight.w600)) : Text(tx('Invoice #${inv.no}', 'فاتورة رقم ${inv.no}')),
      subtitle: Text(inv.dueDate == null || inv.balance <= 0 ? fmtDate(inv.date) : '${fmtDate(inv.date)} · ${tx('due', 'تستحق')} ${fmtDate(inv.dueDate)}'),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(fmtMoney(inv.total), style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        InvoiceStatusChip(inv.status(todayIso())),
      ]),
    );
  }
}

// ---------------------------------------------------------------- detail

class InvoiceDetail extends StatelessWidget {
  const InvoiceDetail({super.key, required this.store, required this.no});
  final WarehouseStore store;
  final int no;

  @override
  Widget build(BuildContext context) {
    final inv = store.invoices.where((i) => i.no == no).firstOrNull;
    if (inv == null) return Scaffold(body: Center(child: Text(tx('This invoice was deleted.', 'تم حذف هذه الفاتورة.'))));
    final t = Theme.of(context);
    final client = store.client(inv.clientId);
    final cost = [for (final (i, _) in inv.lines.indexed) store.invoiceLineCost(inv.no, i)].fold<num>(0, (a, b) => a + b);
    final profit = inv.total - cost;
    final phone = isPhone(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(tx('Invoice #${inv.no}', 'فاتورة رقم ${inv.no}')),
        actions: [
          IconButton(tooltip: tx('Print or share PDF', 'طباعة أو مشاركة PDF'), icon: const Icon(Icons.ios_share), onPressed: () => shareInvoicePdf(store, inv)),
          IconButton(
              tooltip: tx('Edit', 'تعديل'),
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  fullscreenDialog: true, builder: (_) => InvoiceEditor(store: store, existing: inv)))),
          IconButton(
            tooltip: tx('Delete', 'حذف'),
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              if (await confirm(context, tx('Delete invoice #${inv.no}?', 'حذف الفاتورة رقم ${inv.no}؟'),
                  tx('Its items go back into stock and its payments are removed.', 'ترجع موادها إلى المخزون وتُحذف دفعاتها.'))) {
                store.deleteInvoice(inv.no);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: inv.balance > 0
          ? FloatingActionButton.extended(
              onPressed: () => recordPayment(context, store, inv),
              icon: const Icon(Icons.payments_outlined),
              label: Text(tx('Record payment', 'تسجيل دفعة')))
          : null,
      body: PageBody(maxWidth: 860, children: [
        Card(
          child: Padding(
            padding: EdgeInsets.all(phone ? 16 : 22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: NameText(client?.name ?? tx('No client', 'بدون زبون'),
                        style: t.textTheme.titleLarge!.copyWith(fontWeight: FontWeight.w800))),
                InvoiceStatusChip(inv.status(todayIso())),
              ]),
              const SizedBox(height: 4),
              Text(
                  '${tx('Issued', 'صدرت')} ${fmtDate(inv.date)}${inv.dueDate == null ? '' : ' · ${tx('due', 'تستحق')} ${fmtDate(inv.dueDate)}'}',
                  style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
              if (client?.phone != null) Text(client!.phone!, style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 18),
              TileGrid(wideColumns: 3, children: [
                _Mini(tx('Total', 'المجموع'), fmtMoney(inv.total)),
                _Mini(tx('Paid', 'المدفوع'), fmtMoney(inv.paid), color: AppColors.good),
                _Mini(tx('Still owed', 'المتبقي'), fmtMoney(inv.balance), color: inv.balance > 0 ? AppColors.warn : null),
              ]),
            ]),
          ),
        ),
        SectionTitle(tx('Items', 'المواد')),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final (i, l) in inv.lines.indexed) ...[
              if (i > 0) const Divider(height: 1),
              ListTile(
                title: NameText(_lineName(store, l), style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${fmtQty(l.qty)} × ${fmtMoney(l.unitPrice)}'
                    '${l.itemId == null ? ' · ${tx('service', 'خدمة')}' : ' · ${tx('cost', 'الكلفة')} ${fmtMoney(store.invoiceLineCost(inv.no, i))}'}'),
                trailing: Text(fmtMoney(l.total), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
            if (inv.discount != 0) ...[
              const Divider(height: 1),
              ListTile(title: Text(tx('Discount', 'خصم')), trailing: Text('−${fmtMoney(inv.discount)}')),
            ],
          ]),
        ),
        const SizedBox(height: 12),
        Card(
          color: (profit >= 0 ? AppColors.good : AppColors.bad).withValues(alpha: .08),
          child: ListTile(
            leading: Icon(Icons.savings_outlined, color: profit >= 0 ? AppColors.good : AppColors.bad),
            title: Text(tx('You make ${fmtMoney(profit)} on this invoice', 'ربحك ${fmtMoney(profit)} من هذه الفاتورة')),
            subtitle: Text(tx('Sold for ${fmtMoney(inv.total)}; the stock on it cost you ${fmtMoney(cost)} (oldest stock first).',
                'بعتها بـ ${fmtMoney(inv.total)}؛ وكلّفتك المواد فيها ${fmtMoney(cost)} (الأقدم أولاً).')),
          ),
        ),
        SectionTitle(tx('Payments', 'الدفعات'), trailing: Text('${inv.payments.length}')),
        if (inv.payments.isEmpty)
          Card(child: ListTile(title: Text(tx('No payments yet.', 'لا توجد دفعات بعد.'))))
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final (i, p) in inv.payments.indexed) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.check_circle, color: AppColors.good),
                  title: Text(fmtMoney(p.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text([fmtDate(p.date), if (p.method != null) payMethodLabel(p.method!), ?p.note].join(' · ')),
                  trailing: IconButton(
                    tooltip: tx('Remove payment', 'حذف الدفعة'),
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      if (await confirm(context, tx('Remove this payment?', 'حذف هذه الدفعة؟'),
                          tx('${fmtMoney(p.amount)} on ${fmtDate(p.date)}.', '${fmtMoney(p.amount)} بتاريخ ${fmtDate(p.date)}.'),
                          action: tx('Remove', 'حذف'))) {
                        inv.payments.removeAt(i);
                        store.saveInvoice(inv);
                      }
                    },
                  ),
                ),
              ],
            ]),
          ),
        if (inv.note != null) ...[
          SectionTitle(tx('Note', 'ملاحظة')),
          Card(child: Padding(padding: const EdgeInsets.all(16), child: NameText(inv.note!, maxLines: null))),
        ],
      ]),
    );
  }
}

String _lineName(WarehouseStore store, InvoiceLine l) =>
    l.itemId == null ? (l.description ?? tx('Service', 'خدمة')) : (store.item(l.itemId!)?.name ?? l.itemId!);

class _Mini extends StatelessWidget {
  const _Mini(this.label, this.value, {this.color});
  final String label, value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: t.colorScheme.surfaceContainerHighest.withValues(alpha: .5), borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: t.textTheme.labelMedium!.copyWith(color: t.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: t.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w800, color: color))),
      ]),
    );
  }
}

/// Asks for a payment amount (defaults to what is still owed) and adds it to the invoice.
Future<void> recordPayment(BuildContext context, WarehouseStore store, Invoice inv) => showDialog(
      context: context,
      builder: (_) => _PaymentDialog(store: store, inv: inv),
    );

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.store, required this.inv});
  final WarehouseStore store;
  final Invoice inv;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final _amount = TextEditingController(text: widget.inv.balance.round().toString());
  final _note = TextEditingController();
  String _date = todayIso();
  String _method = 'Cash';

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(tx('Payment for invoice #${widget.inv.no}', 'دفعة للفاتورة رقم ${widget.inv.no}')),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tx('Still owed: ${fmtMoney(widget.inv.balance)}', 'المتبقي: ${fmtMoney(widget.inv.balance)}')),
            const SizedBox(height: 14),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tx('Amount received (IQD)', 'المبلغ المستلم (د.ع)')),
            ),
            const SizedBox(height: 12),
            DatePickField(label: tx('Date', 'التاريخ'), value: _date, onChanged: (d) => setState(() => _date = d ?? todayIso())),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final m in ['Cash', 'Bank transfer', 'Card', 'Cheque'])
                ChoiceChip(label: Text(payMethodLabel(m)), selected: _method == m, showCheckmark: false, onSelected: (_) => setState(() => _method = m)),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _note, decoration: InputDecoration(labelText: tx('Note (optional)', 'ملاحظة (اختياري)'))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tx('Cancel', 'إلغاء'))),
          FilledButton(
            onPressed: () {
              final a = parseNum(_amount.text);
              if (a == null || a <= 0) return toast(context, tx('Enter the amount received.', 'أدخل المبلغ المستلم.'));
              final note = _note.text.trim();
              widget.store.addInvoicePayment(
                  widget.inv.no, InvoicePayment(date: _date, amount: a, method: _method, note: note.isEmpty ? null : note));
              Navigator.pop(context);
            },
            child: Text(tx('Save payment', 'حفظ الدفعة')),
          ),
        ],
      );
}

/// A tappable date field. [onChanged] gets null when cleared (only if [clearable]).
class DatePickField extends StatelessWidget {
  const DatePickField({super.key, required this.label, required this.value, required this.onChanged, this.clearable = false});
  final String label;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool clearable;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final d = await showDatePicker(
              context: context,
              initialDate: DateTime.tryParse(value ?? '') ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2100));
          if (d != null) onChanged(isoDate(d));
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: clearable && value != null
                ? IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => onChanged(null))
                : const Icon(Icons.calendar_today_outlined, size: 18),
          ),
          child: Text(value == null ? tx('None', 'لا يوجد') : fmtDate(value)),
        ),
      );
}

// ---------------------------------------------------------------- editor

class _Line {
  _Line({this.itemId, String? description, num? qty, num? price})
      : description = TextEditingController(text: description),
        qty = TextEditingController(text: qty == null ? '1' : fmtQty(qty).replaceAll(',', '')),
        price = TextEditingController(text: price == null ? '' : price.round().toString());
  final String? itemId;
  final TextEditingController description, qty, price;

  num get q => parseNum(qty.text) ?? 0;
  num get p => parseNum(price.text) ?? 0;
  num get total => q * p;
}

class InvoiceEditor extends StatefulWidget {
  const InvoiceEditor({super.key, required this.store, this.existing, this.clientId});
  final WarehouseStore store;
  final Invoice? existing;
  final String? clientId;

  @override
  State<InvoiceEditor> createState() => _InvoiceEditorState();
}

class _InvoiceEditorState extends State<InvoiceEditor> {
  late final WarehouseStore store = widget.store;
  late final Invoice? ex = widget.existing;
  late final _no = TextEditingController(text: '${ex?.no ?? store.nextInvoiceNo}');
  late String _date = ex?.date ?? todayIso();
  late String? _due = ex == null ? isoDate(DateTime.now().add(const Duration(days: 30))) : ex!.dueDate;
  late String? _clientId = ex?.clientId ?? widget.clientId;
  late final _discount = TextEditingController(text: ex == null || ex!.discount == 0 ? '' : ex!.discount.round().toString());
  late final _note = TextEditingController(text: ex?.note);
  late final List<_Line> _lines = [
    for (final l in ex?.lines ?? <InvoiceLine>[]) _Line(itemId: l.itemId, description: l.description, qty: l.qty, price: l.unitPrice),
  ];

  num get _subtotal => _lines.fold<num>(0, (s, l) => s + l.total);
  num get _total => _subtotal - (parseNum(_discount.text) ?? 0);

  /// Cost of the stock on this invoice. Lines of an invoice being edited keep their recorded cost.
  num _lineCost(int i, _Line l) {
    if (l.itemId == null) return 0;
    if (ex != null && i < ex!.lines.length && ex!.lines[i].itemId == l.itemId && ex!.lines[i].qty == l.q) {
      return store.invoiceLineCost(ex!.no, i);
    }
    return store.ledger.estimateCost(l.itemId!, l.q);
  }

  num get _cost => [for (final (i, l) in _lines.indexed) _lineCost(i, l)].fold<num>(0, (a, b) => a + b);

  Future<void> _addItem() async {
    final id = await pickItem(context, store, already: {for (final l in _lines) ?l.itemId});
    if (id == null) return;
    final it = store.item(id);
    // Suggest the item's usual price, else the price it was last sold at.
    num? price = it?.salePrice;
    if (price == null) {
      for (final inv in store.invoices.reversed) {
        final l = inv.lines.where((l) => l.itemId == id).firstOrNull;
        if (l != null) {
          price = l.unitPrice;
          break;
        }
      }
    }
    setState(() => _lines.add(_Line(itemId: id, price: price)));
  }

  void _addService() => setState(() => _lines.add(_Line()));

  Future<void> _pickClient() async {
    final id = await pickClient(context, store);
    if (id != null) setState(() => _clientId = id);
  }

  void _save() {
    final no = int.tryParse(_no.text.trim());
    if (no == null) return toast(context, tx('Enter an invoice number.', 'أدخل رقم الفاتورة.'));
    if (no != ex?.no && store.invoices.any((i) => i.no == no)) return toast(context, tx('Invoice number $no already exists.', 'رقم الفاتورة $no موجود مسبقاً.'));
    if (_clientId == null) return toast(context, tx('Choose the client.', 'اختر الزبون.'));
    final lines = <InvoiceLine>[];
    for (final l in _lines) {
      if (l.q <= 0) return toast(context, tx('Enter a quantity on every line.', 'أدخل الكمية في كل سطر.'));
      final d = l.description.text.trim();
      if (l.itemId == null && d.isEmpty) return toast(context, tx('Describe each service line.', 'اكتب وصفاً لكل سطر خدمة.'));
      lines.add(InvoiceLine(itemId: l.itemId, description: d.isEmpty ? null : d, qty: l.q, unitPrice: l.p));
    }
    if (lines.isEmpty) return toast(context, tx('Add at least one line.', 'أضف سطراً واحداً على الأقل.'));
    final note = _note.text.trim();
    store.saveInvoice(
      Invoice(
        no: no,
        date: _date,
        dueDate: _due,
        clientId: _clientId,
        discount: parseNum(_discount.text) ?? 0,
        note: note.isEmpty ? null : note,
        lines: lines,
        payments: ex?.payments ?? [],
      ),
      replacingNo: ex?.no,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final phone = isPhone(context);
    final client = store.client(_clientId);
    final cost = _cost, profit = _total - cost;

    return Scaffold(
      appBar: AppBar(
        title: Text(ex == null ? tx('New invoice', 'فاتورة جديدة') : tx('Edit invoice #${ex!.no}', 'تعديل الفاتورة رقم ${ex!.no}')),
        actions: [
          Padding(padding: const EdgeInsets.only(right: 12), child: FilledButton(onPressed: _save, child: Text(tx('Save', 'حفظ')))),
        ],
      ),
      body: PageBody(maxWidth: 860, bottomPad: 40, children: [
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            onTap: _pickClient,
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: client == null
                ? Text(tx('Choose client', 'اختر الزبون'), style: const TextStyle(fontWeight: FontWeight.w600))
                : NameText(client.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(client == null
                ? tx('Who are you billing?', 'لمن هذه الفاتورة؟')
                : tx('Owes ${fmtMoney(store.owedBy(client.id))} on other invoices', 'عليه ${fmtMoney(store.owedBy(client.id))} في فواتير أخرى')),
            trailing: const Icon(Icons.chevron_right),
          ),
        ),
        const SizedBox(height: 14),
        _Responsive(phone: phone, children: [
          TextField(controller: _no, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tx('Invoice #', 'رقم الفاتورة'))),
          DatePickField(label: tx('Date', 'التاريخ'), value: _date, onChanged: (d) => setState(() => _date = d ?? _date)),
          DatePickField(label: tx('Pay by', 'تاريخ الاستحقاق'), value: _due, clearable: true, onChanged: (d) => setState(() => _due = d)),
        ]),
        SectionTitle(tx('Lines', 'الأسطر'), trailing: Text(fmtMoney(_subtotal), style: t.textTheme.titleSmall)),
        if (_lines.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                  tx('Add stock items you are selling, or a service line for work or anything not in stock.',
                      'أضف المواد التي تبيعها، أو سطر خدمة لعمل أو لأي شيء غير موجود في المخزون.'),
                  style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
            ),
          ),
        for (final (i, l) in _lines.indexed) _lineCard(i, l, phone),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          FilledButton.tonalIcon(onPressed: _addItem, icon: const Icon(Icons.inventory_2_outlined), label: Text(tx('Add stock item', 'إضافة مادة من المخزون'))),
          OutlinedButton.icon(onPressed: _addService, icon: const Icon(Icons.handyman_outlined), label: Text(tx('Add service', 'إضافة خدمة'))),
        ]),
        const SizedBox(height: 18),
        _Responsive(phone: phone, children: [
          TextField(
            controller: _discount,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: tx('Discount (IQD)', 'خصم (د.ع)')),
          ),
          TextField(controller: _note, decoration: InputDecoration(labelText: tx('Note (optional)', 'ملاحظة (اختياري)'))),
        ]),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(children: [
              _sumRow(tx('Total to bill', 'المبلغ المطلوب'), fmtMoney(_total), bold: true),
              const SizedBox(height: 6),
              _sumRow(tx('Stock cost (oldest first)', 'كلفة المواد (الأقدم أولاً)'), fmtMoney(cost)),
              const Divider(height: 22),
              _sumRow(tx('You make', 'ربحك'), fmtMoney(profit),
                  bold: true,
                  color: profit >= 0 ? AppColors.good : AppColors.bad,
                  hint: _total > 0
                      ? tx('${(profit / _total * 100).toStringAsFixed(0)}% of the invoice', '${(profit / _total * 100).toStringAsFixed(0)}% من الفاتورة')
                      : null),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _sumRow(String label, String value, {bool bold = false, Color? color, String? hint}) => Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontWeight: bold ? FontWeight.w700 : null)),
            if (hint != null) Text(hint, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, fontSize: bold ? 17 : null, color: color)),
      ]);

  Widget _lineCard(int i, _Line l, bool phone) {
    final t = Theme.of(context);
    final item = l.itemId == null ? null : store.item(l.itemId!);
    final cost = _lineCost(i, l);
    final inStock = l.itemId == null ? null : store.stock(l.itemId!).qty + (ex?.lines.where((x) => x.itemId == l.itemId).fold<num>(0, (s, x) => s + x.qty) ?? 0);
    final unitCost = l.q > 0 ? cost / l.q : store.ledger.latestUnitCost(l.itemId ?? '');
    final info = l.itemId == null
        ? tx('Service', 'خدمة')
        : tx('${fmtQty(inStock!)} ${item?.unit ?? ''} in stock · costs you ${unitCost == null ? '?' : fmtMoney(unitCost)} each',
            '${fmtQty(inStock)} ${item?.unit ?? ''} في المخزون · كلفة الواحدة ${unitCost == null ? '?' : fmtMoney(unitCost)}');
    final qty = TextField(
      controller: l.qty,
      onChanged: (_) => setState(() {}),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: tx('Qty', 'الكمية')),
    );
    final price = TextField(
      controller: l.price,
      onChanged: (_) => setState(() {}),
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: tx('Price each (IQD)', 'سعر الواحدة (د.ع)')),
    );
    final remove = IconButton(tooltip: tx('Remove line', 'حذف السطر'), icon: const Icon(Icons.close), onPressed: () => setState(() => _lines.removeAt(i)));
    final name = l.itemId == null
        ? TextField(controller: l.description, decoration: InputDecoration(labelText: tx('What was the service?', 'ما هي الخدمة؟')))
        : NameText(item?.name ?? l.itemId!, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600));
    final lowMargin = l.itemId != null && l.p > 0 && unitCost != null && l.p < unitCost;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Expanded(child: name), remove]),
            const SizedBox(height: 2),
            Text(info, style: t.textTheme.bodySmall!.copyWith(color: inStock != null && inStock < l.q ? AppColors.bad : t.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(children: [
                SizedBox(width: phone ? 80 : 110, child: qty),
                const SizedBox(width: 10),
                Expanded(child: price),
                const SizedBox(width: 10),
                SizedBox(
                  width: phone ? 100 : 160,
                  child: Text(fmtMoney(l.total), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
            if (lowMargin)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(tx('This price is below what the item cost you.', 'هذا السعر أقل من كلفة المادة عليك.'), style: t.textTheme.bodySmall!.copyWith(color: AppColors.bad)),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Fields side by side on wide screens, stacked on phones.
class _Responsive extends StatelessWidget {
  const _Responsive({required this.phone, required this.children});
  final bool phone;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => phone
      ? Column(children: [
          for (final (i, c) in children.indexed) Padding(padding: EdgeInsets.only(top: i == 0 ? 0 : 12), child: c),
        ])
      : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final (i, c) in children.indexed) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: c)],
        ]);
}
