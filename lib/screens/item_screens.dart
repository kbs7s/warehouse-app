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
/// New or edit item form: full screen on phones, a dialog on wider screens.
Future<void> editItem(BuildContext context, WarehouseStore store, Item? item) {
  final size = MediaQuery.sizeOf(context);
  final form = _ItemForm(store: store, item: item);
  return showDialog(
    context: context,
    builder: (_) => size.width < 700
        ? Dialog.fullscreen(child: form)
        : Dialog(
            clipBehavior: Clip.antiAlias,
            child: SizedBox(width: 560, height: size.height * .9 > 780 ? 780 : size.height * .9, child: form),
          ),
  );
}

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
  late final _opening = TextEditingController(text: fmtQty(widget.item?.openingQty ?? 0).replaceAll(',', ''));
  late final _min = TextEditingController(text: fmtQty(widget.item?.minLevel ?? 0).replaceAll(',', ''));
  late final _note = TextEditingController(text: widget.item?.note);
  late final _sale = TextEditingController(text: widget.item?.salePrice?.round().toString());
  late final _openCost = TextEditingController(text: widget.item?.openingUnitCost?.toString());
  late bool _active = widget.item?.active ?? true;

  /// The units used most, for one-tap picking.
  late final List<String> _units = () {
    final count = <String, int>{};
    for (final i in widget.store.items) {
      final u = i.unit.trim();
      if (u.isNotEmpty) count[u] = (count[u] ?? 0) + 1;
    }
    final l = count.keys.toList()..sort((a, b) => count[b]!.compareTo(count[a]!));
    return l.take(8).toList();
  }();

  void _save() {
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
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final isNew = widget.item == null;
    String? numCheck(String? v) => parseNum(v ?? '') == null ? tx('Enter a number', 'أدخل رقماً') : null;
    String? optNum(String? v) => (v ?? '').trim().isEmpty ? null : numCheck(v);
    Widget section(String title, IconData icon, List<Widget> children, {String? hint}) => Card(
          margin: const EdgeInsets.only(bottom: 14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(icon, size: 20, color: t.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: t.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700)),
              ]),
              if (hint != null) ...[
                const SizedBox(height: 4),
                Text(hint, style: TextStyle(color: t.colorScheme.onSurfaceVariant, fontSize: 13)),
              ],
              const SizedBox(height: 14),
              ...children,
            ]),
          ),
        );
    // Two fields side by side when there is room, one under the other on narrow phones.
    Widget pair(Widget a, Widget b) => LayoutBuilder(
          builder: (_, c) => c.maxWidth < 360
              ? Column(children: [a, const SizedBox(height: 12), b])
              : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: a),
                  const SizedBox(width: 12),
                  Expanded(child: b),
                ]),
        );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: tx('Cancel', 'إلغاء'), icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        title: Text(isNew ? tx('New item', 'مادة جديدة') : tx('Edit item', 'تعديل المادة')),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 12),
            child: FilledButton(onPressed: _save, child: Text(tx('Save', 'حفظ'))),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
          section(tx('Item', 'المادة'), Icons.inventory_2_outlined, [
            ListenableBuilder(
              listenable: _name,
              builder: (_, _) => TextFormField(
                controller: _name,
                autofocus: isNew,
                textDirection: dirOf(_name.text),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                decoration: InputDecoration(labelText: tx('Item name', 'اسم المادة'), hintText: tx('Arabic or English', 'بالعربي أو الإنكليزي')),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return tx('Enter a name', 'أدخل الاسم');
                  if (widget.store.nameTaken(v, exceptId: widget.item?.id)) return tx('Another item has this name', 'توجد مادة أخرى بهذا الاسم');
                  return null;
                },
              ),
            ),
            const SizedBox(height: 12),
            pair(
              TextFormField(
                controller: _id,
                enabled: isNew,
                decoration: InputDecoration(labelText: tx('Code', 'الرمز'), prefixIcon: const Icon(Icons.tag, size: 20)),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return tx('Enter a code', 'أدخل الرمز');
                  if (isNew && widget.store.item(v.trim()) != null) return tx('This code is already used', 'هذا الرمز مستخدم');
                  return null;
                },
              ),
              TextFormField(
                controller: _unit,
                decoration: InputDecoration(labelText: tx('Unit', 'الوحدة'), prefixIcon: const Icon(Icons.straighten, size: 20)),
                onChanged: (_) => setState(() {}),
                validator: (v) => (v == null || v.trim().isEmpty) ? tx('Enter a unit', 'أدخل الوحدة') : null,
              ),
            ),
            if (_units.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final u in _units)
                  ChoiceChip(
                    label: Text(u),
                    selected: _unit.text.trim() == u,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _unit.text = u),
                  ),
              ]),
            ],
          ]),
          section(tx('Stock', 'المخزون'), Icons.warehouse_outlined, hint: tx('The app adds purchases and takes away issues by itself.', 'التطبيق يضيف المشتريات ويطرح الصرف تلقائياً.'), [
            pair(
              TextFormField(
                controller: _opening,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tx('Starting quantity', 'الكمية الأولى'), suffixText: _unit.text.trim()),
                validator: numCheck,
              ),
              TextFormField(
                controller: _min,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                    labelText: tx('Warn me below', 'نبّهني إذا قلّ عن'),
                    suffixText: _unit.text.trim(),
                    helperText: tx('0 = no warning', '0 = بدون تنبيه')),
                validator: numCheck,
              ),
            ),
          ]),
          Card(
            margin: const EdgeInsets.only(bottom: 14),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              initiallyExpanded: (widget.item?.salePrice ?? widget.item?.openingUnitCost) != null,
              leading: Icon(Icons.payments_outlined, color: t.colorScheme.primary),
              title: Text(tx('Prices (optional)', 'الأسعار (اختياري)'), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(tx('Only needed for invoices and stock value', 'تحتاجها فقط للفواتير وقيمة المخزون')),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                TextFormField(
                  controller: _sale,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: tx('Selling price', 'سعر البيع'),
                      suffixText: tx('IQD', 'د.ع'),
                      helperText: tx('Suggested when you make an invoice', 'يُقترح عند عمل فاتورة')),
                  validator: optNum,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _openCost,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                      labelText: tx('Cost of each starting unit', 'كلفة الوحدة من الكمية الأولى'),
                      suffixText: tx('IQD', 'د.ع'),
                      helperText: tx('Leave empty to use the first purchase price', 'اتركه فارغاً لاستخدام سعر أول شراء'),
                      helperMaxLines: 2),
                  validator: optNum,
                ),
              ],
            ),
          ),
          section(tx('More', 'المزيد'), Icons.notes_outlined, [
            TextFormField(
              controller: _note,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(labelText: tx('Note', 'ملاحظة')),
            ),
            if (!isNew)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tx('Active (show in lists)', 'فعّالة (تظهر في القوائم)')),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
          ]),
        ]),
      ),
    );
  }
}
