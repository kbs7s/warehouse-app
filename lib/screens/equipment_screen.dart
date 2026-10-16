import 'package:flutter/material.dart';

import '../models.dart';
import '../shell.dart';
import '../store.dart';
import '../ui.dart';

/// Durable surgery tools (Excel sheet Store): how many there are and the dates each was used.
class EquipmentScreen extends StatelessWidget {
  const EquipmentScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Surgery equipment'), bottom: SubNav.bar(context)),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(context, null),
          icon: const Icon(Icons.add),
          label: const Text('New tool'),
        ),
        body: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
          itemCount: store.equipment.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final e = store.equipment[i];
            return ListTile(
              onTap: () => _edit(context, i),
              title: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: NameText(e.name, style: const TextStyle(fontSize: 17))),
              subtitle: Text('Received ${fmtDate(e.dateReceived)} · start ${fmtQty(e.startQty)} · '
                  'bought ${fmtQty(e.boughtQty)} · used ${e.usedQty}'
                  '${e.usageDates.isEmpty ? '' : ' (last ${fmtDate(e.usageDates.last)})'}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${fmtQty(e.nowQty)} now', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: () async {
                    final d = await showDatePicker(
                        context: context,
                        helpText: 'Date used',
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100));
                    if (d == null) return;
                    e.usageDates = [...e.usageDates, isoDate(d)]..sort();
                    store.saveEquipment(e, index: i);
                  },
                  child: const Text('Record use'),
                ),
              ]),
            );
          },
        ),
      );

  Future<void> _edit(BuildContext context, int? index) =>
      showDialog(context: context, builder: (_) => _EquipmentForm(store: store, index: index));
}

class _EquipmentForm extends StatefulWidget {
  const _EquipmentForm({required this.store, this.index});
  final WarehouseStore store;
  final int? index;

  @override
  State<_EquipmentForm> createState() => _EquipmentFormState();
}

class _EquipmentFormState extends State<_EquipmentForm> {
  late final Equipment? _e = widget.index == null ? null : widget.store.equipment[widget.index!];
  late final _name = TextEditingController(text: _e?.name);
  late final _start = TextEditingController(text: fmtQty(_e?.startQty ?? 0));
  late final _bought = TextEditingController(text: fmtQty(_e?.boughtQty ?? 0));
  late String? _received = _e?.dateReceived ?? todayIso();
  late final List<String> _dates = [...?_e?.usageDates];

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_e == null ? 'New surgery tool' : 'Edit tool'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ListenableBuilder(
                listenable: _name,
                builder: (_, _) => TextField(
                    controller: _name,
                    textDirection: dirOf(_name.text),
                    decoration: const InputDecoration(labelText: 'Name')),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _start,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Starting quantity'))),
                const SizedBox(width: 12),
                Expanded(
                    child: TextField(
                        controller: _bought,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Bought since'))),
              ]),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                      context: context,
                      initialDate: DateTime.tryParse(_received ?? '') ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100));
                  if (d != null) setState(() => _received = isoDate(d));
                },
                child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Date received'), child: Text(fmtDate(_received))),
              ),
              const SizedBox(height: 16),
              Text('Used on (${_dates.length})', style: Theme.of(context).textTheme.titleMedium),
              Wrap(spacing: 8, children: [
                for (final d in _dates)
                  InputChip(label: Text(fmtDate(d)), onDeleted: () => setState(() => _dates.remove(d))),
              ]),
            ]),
          ),
        ),
        actions: [
          if (_e != null)
            TextButton(
              onPressed: () async {
                if (await confirm(context, 'Delete this tool?', 'Its usage dates are deleted too.')) {
                  widget.store.deleteEquipment(widget.index!);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: const Text('Delete'),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final start = parseNum(_start.text), bought = parseNum(_bought.text);
              if (_name.text.trim().isEmpty || start == null || bought == null) {
                return toast(context, 'Enter a name and quantities.');
              }
              widget.store.saveEquipment(
                  Equipment(
                      name: _name.text.trim(),
                      dateReceived: _received,
                      startQty: start,
                      boughtQty: bought,
                      usageDates: _dates),
                  index: widget.index);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      );
}
