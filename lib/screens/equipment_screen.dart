import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';
import '../shell.dart';
import '../store.dart';
import '../ui.dart';
import 'item_picker.dart';

/// Durable surgery tools (Excel sheet Store): how many there are, what was bought and what was issued.
class EquipmentScreen extends StatelessWidget {
  const EquipmentScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(tx('Surgery equipment', 'معدات العمليات')), bottom: SubNav.bar(context)),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _edit(context, null),
          icon: const Icon(Icons.add),
          label: Text(tx('New tool', 'أداة جديدة')),
        ),
        body: CardList(
          header: const [],
          empty: tx('No tools yet.', 'لا توجد أدوات بعد.'),
          itemCount: store.equipment.length,
          itemBuilder: (_, i) {
            final e = store.equipment[i];
            final last = [...e.moves]..sort((a, b) => a.date.compareTo(b.date));
            final lastIssue = [...e.usageDates, for (final m in last) if (!m.isBuy) m.date]..sort();
            return InkWell(
              onTap: () => _edit(context, i),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(child: NameText(e.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
                    Text(tx('${fmtQty(e.nowQty)} now', 'الآن ${fmtQty(e.nowQty)}'),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                      tx(
                          'Start ${fmtQty(e.startQty)} · bought ${fmtQty(e.bought)} · issued ${fmtQty(e.issued)}'
                              '${lastIssue.isEmpty ? '' : ' (last ${fmtDate(lastIssue.last)})'}',
                          'البداية ${fmtQty(e.startQty)} · المشترى ${fmtQty(e.bought)} · المصروف ${fmtQty(e.issued)}'
                              '${lastIssue.isEmpty ? '' : ' (آخره ${fmtDate(lastIssue.last)})'}'),
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    FilledButton.tonalIcon(
                      onPressed: () => _move(context, i, buy: true),
                      icon: const Icon(Icons.add_shopping_cart, size: 18),
                      label: Text(tx('Purchase', 'شراء')),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _move(context, i, buy: false),
                      icon: const Icon(Icons.outbox_outlined, size: 18),
                      label: Text(tx('Issue', 'صرف')),
                    ),
                  ]),
                ]),
              ),
            );
          },
        ),
      );

  Future<void> _edit(BuildContext context, int? index) =>
      showDialog(context: context, builder: (_) => _EquipmentForm(store: store, index: index));

  Future<void> _move(BuildContext context, int index, {required bool buy}) async {
    final m = await showDialog<EquipmentMove>(
        context: context, builder: (_) => _MoveDialog(store: store, tool: store.equipment[index], buy: buy));
    if (m == null) return;
    final e = store.equipment[index];
    e.moves = [...e.moves, m]..sort((a, b) => a.date.compareTo(b.date));
    store.saveEquipment(e, index: index);
  }
}

/// Asks how many were bought (and from whom) or issued (and to which department).
class _MoveDialog extends StatefulWidget {
  const _MoveDialog({required this.store, required this.tool, required this.buy});
  final WarehouseStore store;
  final Equipment tool;
  final bool buy;

  @override
  State<_MoveDialog> createState() => _MoveDialogState();
}

class _MoveDialogState extends State<_MoveDialog> {
  final _qty = TextEditingController(text: '1');
  final _supplier = TextEditingController();
  String? _dept;
  String _date = todayIso();

  @override
  Widget build(BuildContext context) {
    final buy = widget.buy;
    return AlertDialog(
      title: Text(buy ? tx('Purchase', 'شراء') : tx('Issue', 'صرف')),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            NameText(widget.tool.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(tx('${fmtQty(widget.tool.nowQty)} in the store now', 'الموجود الآن ${fmtQty(widget.tool.nowQty)}')),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _qty,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: tx('Quantity', 'الكمية'), border: const OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final d = await showDatePicker(
                        context: context, initialDate: DateTime.tryParse(_date) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setState(() => _date = isoDate(d));
                  },
                  child: InputDecorator(
                      decoration: InputDecoration(labelText: tx('Date', 'التاريخ'), border: const OutlineInputBorder()),
                      child: Text(fmtDate(_date))),
                ),
              ),
            ]),
            const SizedBox(height: 14),
            if (buy)
              SuggestField(label: tx('Supplier (optional)', 'المجهز (اختياري)'), controller: _supplier, options: widget.store.suppliers)
            else ...[
              Text(tx('Department', 'القسم'), style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final d in widget.store.departments)
                  ChoiceChip(
                    label: NameText(d),
                    selected: _dept == d,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _dept = _dept == d ? null : d),
                  ),
              ]),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tx('Cancel', 'إلغاء'))),
        FilledButton(
          onPressed: () {
            final q = parseNum(_qty.text);
            if (q == null || q <= 0) return toast(context, tx('Enter the quantity.', 'أدخل الكمية.'));
            if (!buy && q > widget.tool.nowQty) {
              return toast(context, tx('Only ${fmtQty(widget.tool.nowQty)} in the store.', 'الموجود ${fmtQty(widget.tool.nowQty)} فقط.'));
            }
            final s = _supplier.text.trim();
            Navigator.pop(
                context,
                EquipmentMove(
                    date: _date, qty: q, kind: buy ? 'buy' : 'issue', party: buy ? (s.isEmpty ? null : s) : _dept));
          },
          child: Text(tx('Save', 'حفظ')),
        ),
      ],
    );
  }
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
  late final List<EquipmentMove> _moves = [...?_e?.moves];

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_e == null ? tx('New surgery tool', 'أداة عمليات جديدة') : tx('Edit tool', 'تعديل الأداة')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ListenableBuilder(
                listenable: _name,
                builder: (_, _) => TextField(
                    controller: _name,
                    textDirection: dirOf(_name.text),
                    decoration: InputDecoration(labelText: tx('Name', 'الاسم'))),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _start,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: tx('Starting quantity', 'الكمية الأولى')))),
                const SizedBox(width: 12),
                Expanded(
                    child: TextField(
                        controller: _bought,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: tx('Bought before (earlier)', 'المشترى سابقاً')))),
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
                    decoration: InputDecoration(labelText: tx('Date received', 'تاريخ الاستلام')), child: Text(fmtDate(_received))),
              ),
              const SizedBox(height: 16),
              if (_moves.isNotEmpty) ...[
                Text(tx('Purchases and issues', 'الشراء والصرف'), style: Theme.of(context).textTheme.titleMedium),
                for (final m in _moves)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(m.isBuy ? Icons.add_shopping_cart : Icons.outbox_outlined, color: m.isBuy ? Colors.green : null),
                    title: Text('${m.isBuy ? tx('Bought', 'شراء') : tx('Issued', 'صرف')} ${fmtQty(m.qty)} · ${fmtDate(m.date)}'),
                    subtitle: m.party == null ? null : NameText(m.party!),
                    trailing: IconButton(
                        tooltip: tx('Remove', 'حذف'), icon: const Icon(Icons.close), onPressed: () => setState(() => _moves.remove(m))),
                  ),
              ],
              if (_dates.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(tx('Earlier uses (${_dates.length})', 'استخدامات سابقة (${_dates.length})'), style: Theme.of(context).textTheme.titleMedium),
                Wrap(spacing: 8, children: [
                  for (final d in _dates)
                    InputChip(label: Text(fmtDate(d)), onDeleted: () => setState(() => _dates.remove(d))),
                ]),
              ],
            ]),
          ),
        ),
        actions: [
          if (_e != null)
            TextButton(
              onPressed: () async {
                if (await confirm(context, tx('Delete this tool?', 'حذف هذه الأداة؟'), tx('Its usage dates are deleted too.', 'ستُحذف تواريخ استخدامها أيضاً.'))) {
                  widget.store.deleteEquipment(widget.index!);
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: Text(tx('Delete', 'حذف')),
            ),
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tx('Cancel', 'إلغاء'))),
          FilledButton(
            onPressed: () {
              final start = parseNum(_start.text), bought = parseNum(_bought.text);
              if (_name.text.trim().isEmpty || start == null || bought == null) {
                return toast(context, tx('Enter a name and quantities.', 'أدخل الاسم والكميات.'));
              }
              widget.store.saveEquipment(
                  Equipment(
                      name: _name.text.trim(),
                      dateReceived: _received,
                      startQty: start,
                      boughtQty: bought,
                      usageDates: _dates,
                      moves: _moves),
                  index: widget.index);
              Navigator.pop(context);
            },
            child: Text(tx('Save', 'حفظ')),
          ),
        ],
      );
}
