import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../theme.dart';
import '../ui.dart';

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
          final t = Theme.of(context);
          return Scaffold(
            appBar: AppBar(
              title: NameText(s.item.name),
              actions: [
                TextButton.icon(
                    onPressed: () => editItem(context, store, s.item),
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit')),
                const SizedBox(width: 8),
              ],
            ),
            body: PageBody(maxWidth: 900, children: [
              TileGrid(children: [
                MetricTile(label: 'In stock', value: '${fmtQty(s.qty)} ${s.item.unit}', icon: Icons.inventory_2_outlined,
                    color: s.status == StockStatus.inStock ? null : (s.status == StockStatus.low ? AppColors.warn : AppColors.bad),
                    hint: 'Minimum ${fmtQty(s.item.minLevel)}'),
                MetricTile(label: 'Stock value', value: fmtMoneyShort(value), icon: Icons.layers_outlined, hint: 'What it cost you'),
                MetricTile(label: 'Sold', value: fmtQty(s.sold), icon: Icons.sell_outlined,
                    hint: s.item.salePrice == null ? 'No usual price set' : 'Usual price ${fmtMoney(s.item.salePrice!)}'),
                MetricTile(label: 'Given to departments', value: fmtQty(s.issued), icon: Icons.outbox_outlined,
                    hint: 'Opening ${fmtQty(s.item.openingQty)} · bought ${fmtQty(s.bought)}'),
              ]),
              if (s.item.note != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Note: ${s.item.note}')),
              SectionTitle('Cost layers', trailing: Text(s.item.id, style: t.textTheme.bodySmall)),
              Text('Each batch you bought keeps its own price. Sales and issues use the oldest batch first.',
                  style: t.textTheme.bodySmall!.copyWith(color: t.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  if (layers.isEmpty) const ListTile(title: Text('Nothing left in stock.')),
                  for (final (i, l) in layers.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      leading: CircleAvatar(
                          backgroundColor: t.colorScheme.primaryContainer.withValues(alpha: 1 - i * .15 < .3 ? .3 : 1 - i * .15),
                          child: Text('${i + 1}', style: TextStyle(color: t.colorScheme.onPrimaryContainer))),
                      title: NameText(l.source, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${fmtQty(l.qtyLeft)} of ${fmtQty(l.qtyIn)} left · ${fmtMoney(l.unitCost)} each'
                          '${l.date == null ? '' : ' · ${fmtDate(l.date)}'}'
                          '${l.estimatedCost ? (l.unitCost == 0 ? ' · cost unknown' : ' · estimated cost') : ''}'),
                      trailing: Text(fmtMoney(l.valueLeft), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
              ),
              const SectionTitle('Movements'),
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(children: [
                  if (moves.isEmpty) const ListTile(title: Text('No purchases, sales or issues yet.')),
                  for (final (i, m) in moves.indexed) ...[
                    if (i > 0) const Divider(height: 1),
                    ListTile(
                      leading: Icon(m.qty > 0 ? Icons.south_west : Icons.north_east,
                          color: m.qty > 0 ? AppColors.good : (m.kind == 'Invoice' ? AppColors.info : Colors.blueGrey)),
                      title: Row(children: [
                        Text('${m.kind} #${m.no}  ·  '),
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
    String? numCheck(String? v) => parseNum(v ?? '') == null ? 'Enter a number' : null;
    String? optNum(String? v) => (v ?? '').trim().isEmpty ? null : numCheck(v);

    return AlertDialog(
      title: Text(isNew ? 'New item' : 'Edit item'),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: _id,
                enabled: isNew,
                decoration: const InputDecoration(labelText: 'Code'),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Enter a code';
                  if (isNew && widget.store.item(v.trim()) != null) return 'This code is already used';
                  return null;
                },
              ),
              ListenableBuilder(
                listenable: _name,
                builder: (_, _) => TextFormField(
                  controller: _name,
                  autofocus: isNew,
                  textDirection: dirOf(_name.text),
                  decoration: const InputDecoration(labelText: 'Name (Arabic is fine)'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Enter a name';
                    if (widget.store.nameTaken(v, exceptId: widget.item?.id)) return 'Another item has this name';
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
                  decoration: const InputDecoration(labelText: 'Unit (e.g. قطعة, باكيت)'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a unit' : null,
                ),
              ),
              Row(children: [
                Expanded(
                    child: TextFormField(
                        controller: _opening,
                        decoration: const InputDecoration(labelText: 'Opening quantity'),
                        keyboardType: TextInputType.number,
                        validator: numCheck)),
                const SizedBox(width: 16),
                Expanded(
                    child: TextFormField(
                        controller: _min,
                        decoration: const InputDecoration(labelText: 'Minimum level (warn below)'),
                        keyboardType: TextInputType.number,
                        validator: numCheck)),
              ]),
              Row(children: [
                Expanded(
                    child: TextFormField(
                        controller: _sale,
                        decoration: const InputDecoration(labelText: 'Usual selling price (IQD)', helperText: 'Suggested on invoices'),
                        keyboardType: TextInputType.number,
                        validator: optNum)),
                const SizedBox(width: 16),
                Expanded(
                    child: TextFormField(
                        controller: _openCost,
                        decoration: const InputDecoration(labelText: 'Cost of each opening unit', helperText: 'Empty = first purchase price'),
                        keyboardType: TextInputType.number,
                        validator: optNum)),
              ]),
              TextFormField(controller: _note, decoration: const InputDecoration(labelText: 'Note')),
              if (!isNew)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active (show in lists)'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
            ));
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
