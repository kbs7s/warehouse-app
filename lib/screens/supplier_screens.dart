import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';
import '../shell.dart';
import '../store.dart';
import '../theme.dart';
import '../ui.dart';
import 'item_picker.dart';
import 'purchase_screens.dart';

/// What each supplier is still owed for purchases, and the payments made to them.
class SupplierPaymentsScreen extends StatefulWidget {
  const SupplierPaymentsScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  State<SupplierPaymentsScreen> createState() => _SupplierPaymentsScreenState();
}

class _SupplierPaymentsScreenState extends State<SupplierPaymentsScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final names = {for (final p in s.purchases) if (p.tracked) p.supplier ?? ''}.toList();
    final q = _q.trim().toLowerCase();
    final list = names.where((n) => q.isEmpty || n.toLowerCase().contains(q)).toList()
      ..sort((a, b) {
        final c = s.owedTo(b).compareTo(s.owedTo(a));
        return c != 0 ? c : a.compareTo(b);
      });
    final (from, to) = Period.thisMonth.range();
    final paidThisMonth = [
      for (final p in s.purchases)
        for (final x in p.paidLog ?? const <PurchasePaid>[])
          if ((x.date ?? '').compareTo(from) >= 0 && (x.date ?? '').compareTo(to) <= 0) x.amount
    ].fold<num>(0, (a, b) => a + b);

    return Scaffold(
      appBar: AppBar(title: Text(tx('Payments', 'التسديد')), bottom: SubNav.bar(context)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => recordSupplierPayment(context, s),
        icon: const Icon(Icons.payments_outlined),
        label: Text(tx('Record payment', 'تسجيل دفعة')),
      ),
      body: CardList(
        empty: tx('No purchases with payment tracking yet. Add a purchase and its payment shows here.',
            'لا توجد مشتريات بعد. أضف قائمة شراء وسيظهر تسديدها هنا.'),
        header: [
          TileGrid(wideColumns: 3, children: [
            MetricTile(
                label: tx('Still owed', 'المتبقي'),
                value: fmtMoneyShort(s.weOwe),
                icon: Icons.hourglass_bottom,
                color: s.weOwe > 0 ? AppColors.bad : AppColors.good,
                hint: tx('${list.where((n) => s.owedTo(n) > 0).length} suppliers', '${list.where((n) => s.owedTo(n) > 0).length} مجهزين')),
            MetricTile(
                label: tx('Paid this month', 'المدفوع هذا الشهر'),
                value: fmtMoneyShort(paidThisMonth),
                icon: Icons.check_circle_outline,
                color: AppColors.good),
            if (s.openBills.isNotEmpty)
              MetricTile(
                  label: tx('Older bills open', 'قوائم سابقة غير مسددة'),
                  value: '${s.openBills.length}',
                  icon: Icons.history,
                  hint: tx('See "Older bills"', 'انظر "قوائم سابقة"')),
          ]),
          const SizedBox(height: 12),
          SearchField(onChanged: (v) => setState(() => _q = v), hint: tx('Supplier', 'المجهز')),
        ],
        itemCount: list.length,
        itemBuilder: (_, i) {
          final n = list[i];
          final owed = s.owedTo(n);
          final open = s.purchasesOf(n).where((p) => p.owed > 0).length;
          return ListTile(
            leading: const CircleAvatar(child: Icon(Icons.local_shipping_outlined)),
            title: NameText(n.isEmpty ? tx('No supplier', 'بدون مجهز') : n, style: const TextStyle(fontSize: 17)),
            subtitle: Text(open == 0
                ? tx('All purchases paid', 'كل القوائم مسددة')
                : tx('$open purchases not fully paid', '$open قوائم غير مسددة بالكامل')),
            trailing: Text(owed > 0 ? fmtMoney(owed) : tx('Paid', 'مسدد'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: owed > 0 ? AppColors.bad : AppColors.good)),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ListenableBuilder(listenable: s, builder: (_, _) => SupplierAccountScreen(store: s, supplier: n)))),
          );
        },
      ),
    );
  }
}

/// One supplier: their purchases, what is still owed, and every payment.
class SupplierAccountScreen extends StatelessWidget {
  const SupplierAccountScreen({super.key, required this.store, required this.supplier});
  final WarehouseStore store;
  final String supplier;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final mine = store.purchasesOf(supplier).reversed.toList();
    final tracked = mine.where((p) => p.tracked);
    final bought = tracked.fold<num>(0, (a, p) => a + p.total);
    final paid = tracked.fold<num>(0, (a, p) => a + p.paid);
    final owed = store.owedTo(supplier);
    final log = [
      for (final p in mine)
        for (final x in p.paidLog ?? const <PurchasePaid>[]) (p: p, x: x)
    ]..sort((a, b) => (b.x.date ?? '').compareTo(a.x.date ?? ''));
    final bills = [for (final b in store.payments) if ((b.supplier ?? '') == supplier) b];

    return Scaffold(
      appBar: AppBar(title: NameText(supplier.isEmpty ? tx('No supplier', 'بدون مجهز') : supplier)),
      floatingActionButton: owed > 0
          ? FloatingActionButton.extended(
              onPressed: () => recordSupplierPayment(context, store, supplier: supplier),
              icon: const Icon(Icons.payments_outlined),
              label: Text(tx('Record payment', 'تسجيل دفعة')),
            )
          : null,
      body: PageBody(children: [
        TileGrid(wideColumns: 3, children: [
          MetricTile(label: tx('Bought', 'المشتريات'), value: fmtMoneyShort(bought), icon: Icons.shopping_cart_outlined),
          MetricTile(label: tx('Paid', 'المدفوع'), value: fmtMoneyShort(paid), icon: Icons.check_circle_outline, color: AppColors.good),
          MetricTile(
              label: tx('Still owed', 'المتبقي'),
              value: fmtMoneyShort(owed),
              icon: Icons.hourglass_bottom,
              color: owed > 0 ? AppColors.bad : AppColors.good),
        ]),
        SectionTitle(tx('Purchases', 'قوائم الشراء')),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (final p in mine)
              ListTile(
                leading: CircleAvatar(child: Text('${p.no}')),
                title: Text(fmtDate(p.date)),
                subtitle: Text([
                  tx('${p.lines.length} items', '${p.lines.length} مادة'),
                  if (p.ref != null) tx('bill ${p.ref}', 'قائمة ${p.ref}'),
                ].join('  ·  ')),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(fmtMoney(p.total), style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (p.tracked) PayStatus(p),
                ]),
                onTap: () => openPurchase(context, store, p),
              ),
          ]),
        ),
        SectionTitle(tx('Payments made', 'الدفعات')),
        if (log.isEmpty)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(tx('No payments recorded yet.', 'لا توجد دفعات مسجلة بعد.'), style: t.textTheme.bodyMedium),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final e in log)
                ListTile(
                  leading: const Icon(Icons.payments_outlined, color: AppColors.good),
                  title: Text(fmtMoney(e.x.amount), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text([
                    fmtDate(e.x.date),
                    tx('purchase #${e.p.no}', 'شراء رقم ${e.p.no}'),
                    if (e.x.note != null) e.x.note!,
                  ].join('  ·  ')),
                  onTap: () => openPurchase(context, store, e.p),
                ),
            ]),
          ),
        if (bills.isNotEmpty) ...[
          SectionTitle(tx('Older bills', 'قوائم سابقة')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final b in bills)
                ListTile(
                  title: Text(fmtDate(b.date)),
                  subtitle: b.details == null ? null : NameText(b.details!, maxLines: 2),
                  trailing: Text(b.settled ? tx('Paid', 'مسددة') : tx('Owed ${fmtQty(b.remaining)}', 'متبقي ${fmtQty(b.remaining)}'),
                      style: TextStyle(color: b.settled ? AppColors.good : AppColors.bad, fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// Records money paid to a supplier; it settles their oldest unpaid purchases first.
Future<void> recordSupplierPayment(BuildContext context, WarehouseStore store, {String? supplier}) =>
    showDialog(context: context, builder: (_) => _SupplierPayDialog(store: store, supplier: supplier));

class _SupplierPayDialog extends StatefulWidget {
  const _SupplierPayDialog({required this.store, this.supplier});
  final WarehouseStore store;
  final String? supplier;

  @override
  State<_SupplierPayDialog> createState() => _SupplierPayDialogState();
}

class _SupplierPayDialogState extends State<_SupplierPayDialog> {
  late final _supplier = TextEditingController(text: widget.supplier);
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _date = todayIso();

  @override
  void initState() {
    super.initState();
    _supplier.addListener(() => setState(() {}));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final name = _supplier.text.trim();
    final owed = s.owedTo(name);
    final owing = [for (final n in {for (final p in s.purchases) if (p.owed > 0) p.supplier ?? ''}) if (n.isNotEmpty) n];
    return AlertDialog(
      title: Text(tx('Record payment', 'تسجيل دفعة')),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.supplier == null)
            SuggestField(label: tx('Supplier', 'المجهز'), controller: _supplier, options: owing)
          else
            NameText(widget.supplier!, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (name.isNotEmpty)
            Text(owed > 0 ? tx('Still owed: ${fmtMoney(owed)}', 'المتبقي: ${fmtMoney(owed)}') : tx('Nothing is owed to this supplier.', 'لا يوجد مبلغ متبقٍ لهذا المجهز.'),
                style: TextStyle(color: owed > 0 ? AppColors.bad : null, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: tx('Amount paid (IQD)', 'المبلغ المدفوع (د.ع)'), border: const OutlineInputBorder()),
              ),
            ),
            if (owed > 0) ...[
              const SizedBox(width: 8),
              TextButton(
                  onPressed: () => _amount.text = '$owed', child: Text(tx('All of it', 'كامل المبلغ'))),
            ],
          ]),
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
          const SizedBox(height: 8),
          Text(tx('The oldest unpaid purchases are settled first.', 'تُسدَّد أقدم القوائم غير المسددة أولاً.'),
              style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tx('Cancel', 'إلغاء'))),
        FilledButton(
          onPressed: () {
            final a = parseNum(_amount.text);
            if (owed <= 0) return toast(context, tx('Choose a supplier who is still owed money.', 'اختر مجهزاً له مبلغ متبقٍ.'));
            if (a == null || a <= 0) return toast(context, tx('Enter the amount paid.', 'أدخل المبلغ المدفوع.'));
            if (a > owed) return toast(context, tx('That is more than the ${fmtMoney(owed)} owed.', 'هذا أكثر من المتبقي ${fmtMoney(owed)}.'));
            final n = _note.text.trim();
            s.paySupplier(name, a, date: _date, note: n.isEmpty ? null : n);
            Navigator.pop(context);
            toast(context, tx('Payment of ${fmtMoney(a)} recorded.', 'سُجّلت دفعة ${fmtMoney(a)}.'));
          },
          child: Text(tx('Save', 'حفظ')),
        ),
      ],
    );
  }
}
