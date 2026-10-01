import 'package:flutter/material.dart';

import '../models.dart';
import '../store.dart';
import '../ui.dart';

/// Searchable list of items; returns the chosen item id, or null.
Future<String?> pickItem(BuildContext context, WarehouseStore store, {Set<String> already = const {}}) =>
    showDialog<String>(context: context, builder: (_) => _ItemPicker(store: store, already: already));

class _ItemPicker extends StatefulWidget {
  const _ItemPicker({required this.store, required this.already});
  final WarehouseStore store;
  final Set<String> already;

  @override
  State<_ItemPicker> createState() => _ItemPickerState();
}

class _ItemPickerState extends State<_ItemPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = widget.store.stockList
        .where((s) => q.isEmpty || s.item.name.toLowerCase().contains(q) || s.item.id.toLowerCase().contains(q))
        .toList();
    return Dialog(
      child: SizedBox(
        width: 600,
        height: 640,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                  hintText: 'Type part of the item name', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final s = list[i];
                final added = widget.already.contains(s.item.id);
                return ListTile(
                  enabled: !added,
                  title: Align(alignment: AlignmentDirectional.centerStart, child: NameText(s.item.name, style: const TextStyle(fontSize: 17))),
                  subtitle: Text(added ? '${s.item.id} · already on this list' : s.item.id),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${fmtQty(s.qty)} ', style: const TextStyle(fontWeight: FontWeight.w600)),
                    NameText(s.item.unit),
                    const SizedBox(width: 8),
                    if (s.status != StockStatus.inStock) StatusChip(s.status),
                  ]),
                  onTap: () => Navigator.pop(context, s.item.id),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))),
          ),
        ]),
      ),
    );
  }
}

/// Free-text field with suggestions (departments, people, suppliers). Arabic or English.
class SuggestField extends StatefulWidget {
  const SuggestField({super.key, required this.label, required this.controller, required this.options});
  final String label;
  final TextEditingController controller;
  final List<String> options;

  @override
  State<SuggestField> createState() => _SuggestFieldState();
}

class _SuggestFieldState extends State<SuggestField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RawAutocomplete<String>(
        textEditingController: widget.controller,
        focusNode: _focus,
        optionsBuilder: (v) => widget.options.where((o) => o.toLowerCase().contains(v.text.trim().toLowerCase())),
        fieldViewBuilder: (context, c, focus, _) => ListenableBuilder(
          listenable: c,
          builder: (_, _) => TextField(
            controller: c,
            focusNode: focus,
            textDirection: dirOf(c.text),
            decoration: InputDecoration(labelText: widget.label, border: const OutlineInputBorder()),
          ),
        ),
        optionsViewBuilder: (context, onSelected, opts) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 400),
              child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
                for (final o in opts)
                  ListTile(dense: true, title: NameText(o), onTap: () => onSelected(o)),
              ]),
            ),
          ),
        ),
      );
}
