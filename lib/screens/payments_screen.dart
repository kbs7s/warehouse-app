import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';
import '../shell.dart';
import '../store.dart';
import '../ui.dart';
import 'item_picker.dart';

/// Supplier invoices and what is still owed (Excel sheet تسديد).
class PaymentsScreen extends StatefulWidget {
  const PaymentsScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen> {
  bool _unpaidOnly = false;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final all = store.payments;
    final q = _q.trim();
    final list = all.reversed
        .where((p) => !_unpaidOnly || !p.settled)
        .where((p) => q.isEmpty || (p.supplier ?? '').contains(q) || (p.details ?? '').contains(q))
        .toList();
    num sum(num Function(Payment) f) => all.fold<num>(0, (s, p) => s + f(p));

    return Scaffold(
      appBar: AppBar(title: Text(tx('Supplier payments', 'فواتير المجهزين')), bottom: SubNav.bar(context)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, null),
        icon: const Icon(Icons.add),
        label: Text(tx('New invoice', 'فاتورة جديدة')),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(spacing: 12, runSpacing: 12, children: [
            _Total(tx('Total', 'المجموع'), sum((p) => p.amount)),
            _Total(tx('Paid', 'المدفوع'), sum((p) => p.paid), color: Colors.green),
            _Total(tx('Still owed', 'المتبقي'), sum((p) => p.remaining), color: Colors.red),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: SearchField(onChanged: (v) => setState(() => _q = v), hint: tx('Supplier or details', 'المجهز أو التفاصيل'))),
            const SizedBox(width: 12),
            FilterChip(
                label: Text(tx('Unpaid only', 'غير المسددة فقط')),
                selected: _unpaidOnly,
                onSelected: (v) => setState(() => _unpaidOnly = v)),
          ]),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 96),
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final p = list[i];
                return ListTile(
                  onTap: () => _edit(context, p),
                  leading: CircleAvatar(child: Text('${p.no}')),
                  title: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: NameText(p.supplier ?? '—', style: const TextStyle(fontSize: 17))),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(fmtDate(p.date)),
                    if (p.details != null) NameText(p.details!, maxLines: 2),
                  ]),
                  isThreeLine: p.details != null,
                  trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(fmtQty(p.amount), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                        Text(p.settled ? tx('Paid', 'مسددة') : tx('Owed ${fmtQty(p.remaining)}', 'متبقي ${fmtQty(p.remaining)}'),
                            style: TextStyle(color: p.settled ? Colors.green : Colors.red)),
                      ]),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _edit(BuildContext context, Payment? p) =>
      showDialog(context: context, builder: (_) => _PaymentForm(store: widget.store, existing: p));
}

class _Total extends StatelessWidget {
  const _Total(this.label, this.value, {this.color});
  final String label;
  final num value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: Colors.grey.shade700)),
            Text(fmtQty(value),
                style: Theme.of(context).textTheme.headlineSmall!.copyWith(color: color, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

class _PaymentForm extends StatefulWidget {
  const _PaymentForm({required this.store, this.existing});
  final WarehouseStore store;
  final Payment? existing;

  @override
  State<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<_PaymentForm> {
  late final _supplier = TextEditingController(text: widget.existing?.supplier);
  late final _amount = TextEditingController(text: widget.existing == null ? '' : '${widget.existing!.amount}');
  late final _paid = TextEditingController(text: widget.existing == null ? '0' : '${widget.existing!.paid}');
  late final _details = TextEditingController(text: widget.existing?.details);
  late String? _date = widget.existing?.date ?? todayIso();

  @override
  Widget build(BuildContext context) {
    final e = widget.existing;
    return AlertDialog(
      title: Text(e == null ? tx('New supplier invoice', 'فاتورة مجهز جديدة') : tx('Invoice #${e.no}', 'فاتورة رقم ${e.no}')),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SuggestField(label: tx('Supplier', 'المجهز'), controller: _supplier, options: widget.store.suppliers),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(
                  context: context,
                  initialDate: DateTime.tryParse(_date ?? '') ?? DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100));
              if (d != null) setState(() => _date = isoDate(d));
            },
            child: InputDecorator(decoration: InputDecoration(labelText: tx('Date', 'التاريخ')), child: Text(fmtDate(_date))),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: tx('Amount', 'المبلغ')))),
            const SizedBox(width: 12),
            Expanded(
                child: TextField(
                    controller: _paid,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: tx('Paid so far', 'المدفوع حتى الآن')))),
            const SizedBox(width: 8),
            TextButton(onPressed: () => _paid.text = _amount.text, child: Text(tx('Paid in full', 'مدفوعة بالكامل'))),
          ]),
          const SizedBox(height: 12),
          ListenableBuilder(
            listenable: _details,
            builder: (_, _) => TextField(
                controller: _details,
                maxLines: 3,
                textDirection: dirOf(_details.text),
                decoration: InputDecoration(labelText: tx('Details', 'التفاصيل'))),
          ),
        ]),
      ),
      actions: [
        if (e != null)
          TextButton(
            onPressed: () async {
              if (await confirm(context, tx('Delete invoice #${e.no}?', 'حذف الفاتورة رقم ${e.no}؟'), tx('This cannot be undone.', 'لا يمكن التراجع عن هذا.'))) {
                widget.store.deletePayment(e.no);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: Text(tx('Delete', 'حذف')),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tx('Cancel', 'إلغاء'))),
        FilledButton(
          onPressed: () {
            final amount = parseNum(_amount.text), paid = parseNum(_paid.text.isEmpty ? '0' : _paid.text);
            if (_supplier.text.trim().isEmpty || amount == null || paid == null) {
              return toast(context, tx('Enter the supplier, amount and paid amount.', 'أدخل المجهز والمبلغ والمدفوع.'));
            }
            final details = _details.text.trim();
            widget.store.savePayment(
                Payment(
                    no: e?.no ?? widget.store.nextPaymentNo,
                    supplier: _supplier.text.trim(),
                    date: _date,
                    amount: amount,
                    paid: paid,
                    details: details.isEmpty ? null : details),
                replacingNo: e?.no);
            Navigator.pop(context);
          },
          child: Text(tx('Save', 'حفظ')),
        ),
      ],
    );
  }
}
