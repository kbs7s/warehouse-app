import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
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
          return Scaffold(
            appBar: AppBar(
              title: NameText(s.item.name),
              actions: [
                TextButton.icon(
                    onPressed: () => editItem(context, store, s.item),
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit')),
              ],
            ),
            body: ListView(padding: const EdgeInsets.all(16), children: [
              Wrap(spacing: 12, runSpacing: 12, children: [
                _Stat('In stock', '${fmtQty(s.qty)} ${s.item.unit}', trailing: StatusChip(s.status)),
                _Stat('Opening', fmtQty(s.item.openingQty)),
                _Stat('Bought', fmtQty(s.bought)),
                _Stat('Issued', fmtQty(s.issued)),
                _Stat('Minimum', fmtQty(s.item.minLevel)),
                _Stat('Code', s.item.id),
              ]),
              if (s.item.note != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Note: ${s.item.note}')),
              const SizedBox(height: 24),
              Text('Movements', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (moves.isEmpty) const Text('No purchases or issues yet.'),
              for (final m in moves)
                ListTile(
                  leading: Icon(m.qty > 0 ? Icons.south_west : Icons.north_east,
                      color: m.qty > 0 ? Colors.green : Colors.blueGrey),
                  title: Row(children: [
                    Text('${m.kind} #${m.no}  ·  '),
                    Flexible(child: NameText(m.party)),
                  ]),
                  subtitle: Text(fmtDate(m.date)),
                  trailing: Text((m.qty > 0 ? '+' : '') + fmtQty(m.qty),
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600, color: m.qty > 0 ? Colors.green : null)),
                ),
            ]),
          );
        },
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.trailing});
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            Row(mainAxisSize: MainAxisSize.min, children: [
              NameText(value, style: Theme.of(context).textTheme.titleLarge),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ]),
          ]),
        ),
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
  late bool _active = widget.item?.active ?? true;

  @override
  Widget build(BuildContext context) {
    final isNew = widget.item == null;
    final units = {for (final i in widget.store.items) i.unit}.where((u) => u.isNotEmpty).toList()..sort();
    String? numCheck(String? v) => parseNum(v ?? '') == null ? 'Enter a number' : null;

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
            ));
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
