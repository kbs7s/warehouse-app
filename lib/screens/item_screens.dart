import 'package:flutter/material.dart';

import '../export.dart' show avgMonthlyUse;
import '../l10n.dart';
import '../models.dart';
import '../month.dart';
import '../store.dart';
import '../theme.dart';
import '../ui.dart';
import 'expiry_screens.dart';

class ItemDetailScreen extends StatelessWidget {
  const ItemDetailScreen({super.key, required this.store, required this.itemId});
  final WarehouseStore store;
  final String itemId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final s = store.stock(itemId);
          final moves = store.movements(itemId);
          final layers = store.ledger.layers[itemId] ?? const [];
          final value = store.ledger.itemValue(itemId);
          final avg = avgMonthlyUse(store.monthlyIssued()[itemId], DateTime.now());
          final t = Theme.of(context);
          return Scaffold(
            appBar: AppBar(
              title: NameText(s.item.name),
              actions: [
                TextButton.icon(
                    onPressed: () => editItem(context, store, s.item),
                    icon: const Icon(Icons.edit),
                    label: Text(tx('Edit', 'تعديل'))),
                const SizedBox(width: 8),
              ],
            ),
            body: PageBody(maxWidth: 900, children: [
              TileGrid(children: [
                MetricTile(label: tx('In stock', 'الموجود'), value: '${fmtQty(s.qty)} ${s.item.unit}', icon: Icons.inventory_2_outlined,
                    color: s.status == StockStatus.inStock ? null : (s.status == StockStatus.low ? AppColors.warn : AppColors.bad),
                    hint: tx('Minimum ${fmtQty(s.item.minLevel)}', 'الحد الأدنى ${fmtQty(s.item.minLevel)}')),
                MetricTile(
                    label: tx('Stock value', 'قيمة المخزون'),
                    value: fmtMoneyShort(value),
                    icon: Icons.layers_outlined,
                    hint: tx('What it cost you', 'ما كلّفك')),
                if (s.sold > 0 || s.item.salePrice != null)
                  MetricTile(label: tx('Sold', 'المباع'), value: fmtQty(s.sold), icon: Icons.sell_outlined,
                      hint: s.item.salePrice == null
                          ? tx('No usual price set', 'لا يوجد سعر بيع معتاد')
                          : tx('Usual price ${fmtMoney(s.item.salePrice!)}', 'سعر البيع المعتاد ${fmtMoney(s.item.salePrice!)}'))
                else
                  MetricTile(
                      label: tx('Used per month', 'الاستهلاك الشهري'),
                      value: '~${fmtQty(avg.round())}',
                      icon: Icons.speed_outlined,
                      hint: avg <= 0
                          ? tx('Not issued in the last 3 months', 'لم يُصرف خلال آخر 3 أشهر')
                          : s.qty <= 0
                              ? tx('Order now', 'اطلب الآن')
                              : s.qty < avg
                                  ? tx('Lasts less than a month', 'يكفي أقل من شهر')
                                  : tx('Lasts about ${fmtQty((s.qty / avg * 10).round() / 10)} months', 'يكفي قرابة ${fmtQty((s.qty / avg * 10).round() / 10)} شهر')),
                MetricTile(
                    label: tx('Spent this month', 'مصروف الشهر'),
                    value: fmtQty(store.spentThisMonth[itemId] ?? 0),
                    icon: Icons.outbox_outlined,
                    hint: tx('This year ${fmtQty(store.spentThisYear[itemId] ?? 0)} · all time ${fmtQty(s.issued + s.sold)}',
                        'هذه السنة ${fmtQty(store.spentThisYear[itemId] ?? 0)} · الكلي ${fmtQty(s.issued + s.sold)}')),
              ]),
              if (s.item.note != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(tx('Note: ${s.item.note}', 'ملاحظة: ${s.item.note}'))),
              ItemExpirySection(store: store, item: s.item),
              SectionTitle(tx('Cost layers', 'دفعات الكلفة'), trailing: Text(s.item.id, style: t.textTheme.bodySmall)),
              Text(
                  tx('Each batch you bought keeps its own price. Sales and issues use the oldest batch first.',
                      'كل دفعة اشتريتها تحتفظ بسعرها. البيع والصرف يأخذان من أقدم دفعة أولاً.'),
                  style: t.textTheme.bodySmall!.copyWith(color: t.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  if (layers.isEmpty) ListTile(title: Text(tx('Nothing left in stock.', 'لم يبقَ شيء في المخزون.'))),
                  for (final (i, l) in layers.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      leading: CircleAvatar(
                          backgroundColor: t.colorScheme.primaryContainer.withValues(alpha: 1 - i * .15 < .3 ? .3 : 1 - i * .15),
                          child: Text('${i + 1}', style: TextStyle(color: t.colorScheme.onPrimaryContainer))),
                      title: NameText(_source(l.source), style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(tx('${fmtQty(l.qtyLeft)} of ${fmtQty(l.qtyIn)} left · ${fmtMoney(l.unitCost)} each',
                              'باقي ${fmtQty(l.qtyLeft)} من ${fmtQty(l.qtyIn)} · ${fmtMoney(l.unitCost)} للوحدة') +
                          (l.date == null ? '' : ' · ${fmtDate(l.date)}') +
                          (l.estimatedCost
                              ? (l.unitCost == 0 ? tx(' · cost unknown', ' · الكلفة غير معروفة') : tx(' · estimated cost', ' · كلفة تقديرية'))
                              : '')),
                      trailing: Text(fmtMoney(l.valueLeft), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
              ),
              SectionTitle(tx('Movements', 'الحركات')),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  if (moves.isEmpty) ListTile(title: Text(tx('No purchases, sales or issues yet.', 'لا توجد مشتريات أو مبيعات أو صرف بعد.'))),
                  for (final (i, m) in moves.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      leading: Icon(m.qty > 0 ? Icons.south_west : Icons.north_east,
                          color: m.qty > 0 ? AppColors.good : (m.kind == 'Invoice' ? AppColors.info : Colors.blueGrey)),
                      title: Row(children: [
                        Text('${_kind(m.kind)} #${m.no}  ·  '),
                        Flexible(child: NameText(m.party)),
                      ]),
                      subtitle: Text(fmtDate(m.date)),
                      trailing: Text((m.qty > 0 ? '+' : '') + fmtQty(m.qty),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: m.qty > 0 ? AppColors.good : null)),
                    ),
                  ],
                ]),
              ),
            ]),
          );
        },
      );
}

/// Movement kinds come from the store in English; shown in the interface language.
String _kind(String k) => switch (k) {
      'Purchase' => tx('Purchase', 'شراء'),
      'Issue' => tx('Issue', 'صرف'),
      'Invoice' => tx('Invoice', 'فاتورة'),
      _ => k,
    };

/// Cost layer sources are built in the ledger in English ("Opening stock", "Purchase #3 · supplier").
String _source(String s) {
  if (!isAr) return s;
  if (s == 'Opening stock') return 'رصيد افتتاحي';
  for (final k in const ['Purchase', 'Issue', 'Invoice']) {
    if (s.startsWith('$k #')) return _kind(k) + s.substring(k.length);
  }
  return s;
}

/// Opens the add/edit item form. [item] null means a new item.
Future<void> editItem(BuildContext context, WarehouseStore store, Item? item) => showDialog(
      context: context,
      builder: (_) => _ItemForm(store: store, item: item),
    );

class _ItemForm extends StatefulWidget {
  const _ItemForm({required this.store, this.item});
  final WarehouseStore store;
  final Item? item;

  @override
  State<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends State<_ItemForm> {
  final _form = GlobalKey<FormState>();
  late final _id = TextEditingController(text: widget.item?.id ?? widget.store.nextItemId);
  late final _name = TextEditingController(text: widget.item?.name);
  late final _unit = TextEditingController(text: widget.item?.unit);
  late final _opening = TextEditingController(text: fmtQty(widget.item?.openingQty ?? 0));
  late final _min = TextEditingController(text: fmtQty(widget.item?.minLevel ?? 0));
  late final _note = TextEditingController(text: widget.item?.note);
  late final _sale = TextEditingController(text: widget.item?.salePrice?.round().toString());
  late final _openCost = TextEditingController(text: widget.item?.openingUnitCost?.toString());
  late bool _active = widget.item?.active ?? true;

  @override
  Widget build(BuildContext context) {
    final isNew = widget.item == null;
    final units = {for (final i in widget.store.items) i.unit}.where((u) => u.isNotEmpty).toList()..sort();
    String? numCheck(String? v) => parseNum(v ?? '') == null ? tx('Enter a number', 'أدخل رقماً') : null;
    String? optNum(String? v) => (v ?? '').trim().isEmpty ? null : numCheck(v);

    return AlertDialog(
      title: Text(isNew ? tx('New item', 'مادة جديدة') : tx('Edit item', 'تعديل المادة')),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _id,
                enabled: isNew,
                decoration: InputDecoration(labelText: tx('Code', 'الرمز')),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return tx('Enter a code', 'أدخل الرمز');
                  if (isNew && widget.store.item(v.trim()) != null) return tx('This code is already used', 'هذا الرمز مستخدم');
                  return null;
                },
              ),
              ListenableBuilder(
                listenable: _name,
                builder: (_, _) => TextFormField(
                  controller: _name,
                  autofocus: isNew,
                  textDirection: dirOf(_name.text),
                  decoration: InputDecoration(labelText: tx('Name (Arabic is fine)', 'الاسم')),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return tx('Enter a name', 'أدخل الاسم');
                    if (widget.store.nameTaken(v, exceptId: widget.item?.id)) return tx('Another item has this name', 'توجد مادة أخرى بهذا الاسم');
                    return null;
                  },
                ),
              ),
              Autocomplete<String>(
                initialValue: TextEditingValue(text: _unit.text),
                optionsBuilder: (v) => units.where((u) => u.contains(v.text)),
                onSelected: (v) => _unit.text = v,
                fieldViewBuilder: (context, c, focus, onSubmit) => TextFormField(
                  controller: c,
                  focusNode: focus,
                  onChanged: (v) => _unit.text = v,
                  decoration: InputDecoration(labelText: tx('Unit (e.g. قطعة, باكيت)', 'الوحدة (مثل قطعة، باكيت)')),
                  validator: (v) => (v == null || v.trim().isEmpty) ? tx('Enter a unit', 'أدخل الوحدة') : null,
                ),
              ),
              Row(children: [
                Expanded(
                    child: TextFormField(
                        controller: _opening,
                        decoration: InputDecoration(labelText: tx('Opening quantity', 'الكمية الافتتاحية')),
                        keyboardType: TextInputType.number,
                        validator: numCheck)),
                const SizedBox(width: 16),
                Expanded(
                    child: TextFormField(
                        controller: _min,
                        decoration: InputDecoration(labelText: tx('Minimum level (warn below)', 'الحد الأدنى (تنبيه دونه)')),
                        keyboardType: TextInputType.number,
                        validator: numCheck)),
              ]),
              Row(children: [
                Expanded(
                    child: TextFormField(
                        controller: _sale,
                        decoration: InputDecoration(
                            labelText: tx('Usual selling price (IQD)', 'سعر البيع المعتاد (د.ع)'),
                            helperText: tx('Suggested on invoices', 'يُقترح في الفواتير')),
                        keyboardType: TextInputType.number,
                        validator: optNum)),
                const SizedBox(width: 16),
                Expanded(
                    child: TextFormField(
                        controller: _openCost,
                        decoration: InputDecoration(
                            labelText: tx('Cost of each opening unit', 'كلفة الوحدة الافتتاحية'),
                            helperText: tx('Empty = first purchase price', 'فارغ = سعر أول شراء')),
                        keyboardType: TextInputType.number,
                        validator: optNum)),
              ]),
              TextFormField(controller: _note, decoration: InputDecoration(labelText: tx('Note', 'ملاحظة'))),
              if (!isNew)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tx('Active (show in lists)', 'فعّالة (تظهر في القوائم)')),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tx('Cancel', 'إلغاء'))),
        FilledButton(
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            final note = _note.text.trim();
            widget.store.saveItem(Item(
              id: _id.text.trim(),
              name: _name.text.trim(),
              unit: _unit.text.trim(),
              openingQty: parseNum(_opening.text)!,
              minLevel: parseNum(_min.text)!,
              category: widget.item?.category,
              active: _active,
              note: note.isEmpty ? null : note,
              salePrice: parseNum(_sale.text),
              openingUnitCost: parseNum(_openCost.text),
              expiries: widget.item?.expiries,
            ));
            Navigator.pop(context);
          },
          child: Text(tx('Save', 'حفظ')),
        ),
      ],
    );
  }
}
