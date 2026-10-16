import 'package:flutter/material.dart';

import '../models.dart';
import '../shell.dart';
import '../store.dart';
import '../theme.dart';
import '../ui.dart';
import 'invoice_screens.dart' show DatePickField;

/// Running costs of the business (rent, salaries, electricity...), by period.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  Period _period = Period.thisMonth;

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final t = Theme.of(context);
    final (from, to) = _period.range();
    final list = [for (final e in s.expenses.reversed) if (e.date.compareTo(from) >= 0 && e.date.compareTo(to) <= 0) e];
    final total = list.fold<num>(0, (a, e) => a + e.amount);
    final byCat = <String, num>{};
    for (final e in list) {
      byCat[e.category] = (byCat[e.category] ?? 0) + e.amount;
    }
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(title: const Text('Expenses'), bottom: SubNav.bar(context)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openExpense(context, s, null),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
      body: PageBody(children: [
        PeriodChips(value: _period, onChanged: (p) => setState(() => _period = p)),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Spent on running the business', style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Text(fmtMoney(total), style: t.textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w800)),
              if (cats.isNotEmpty) const SizedBox(height: 16),
              for (final c in cats) ShareBar(label: c.key, value: c.value, total: total),
            ]),
          ),
        ),
        SectionTitle('Entries', trailing: Text('${list.length}')),
        if (list.isEmpty)
          const EmptyState(
            icon: Icons.payments_outlined,
            title: 'No expenses in this period',
            message: 'Record rent, salaries, electricity and other running costs so profit is real.',
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final (i, e) in list.indexed) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  onTap: () => openExpense(context, s, e),
                  leading: CircleAvatar(
                      backgroundColor: t.colorScheme.tertiaryContainer,
                      child: Icon(categoryIcon(e.category), color: t.colorScheme.onTertiaryContainer, size: 20)),
                  title: Text(e.category, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text([fmtDate(e.date), ?e.note].join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Text(fmtMoney(e.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ),
      ]),
    );
  }
}

IconData categoryIcon(String c) => switch (c.toLowerCase()) {
      'rent' => Icons.home_work_outlined,
      'salaries' => Icons.badge_outlined,
      'electricity' => Icons.bolt,
      'transport' => Icons.local_shipping_outlined,
      'maintenance' => Icons.build_outlined,
      _ => Icons.sell_outlined,
    };

/// Period choice chips shared by the money screens.
class PeriodChips extends StatelessWidget {
  const PeriodChips({super.key, required this.value, required this.onChanged});
  final Period value;
  final ValueChanged<Period> onChanged;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final p in Period.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(label: Text(p.label), selected: p == value, showCheckmark: false, onSelected: (_) => onChanged(p)),
            ),
        ]),
      );
}

/// One labelled bar showing a part of a total.
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.label, required this.value, required this.total, this.color});
  final String label;
  final num value, total;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final f = total <= 0 ? 0.0 : (value / total).clamp(0, 1).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: NameText(label)),
          Text('${fmtMoney(value)}  ·  ${(f * 100).toStringAsFixed(0)}%', style: t.textTheme.bodySmall),
        ]),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: f,
            minHeight: 8,
            color: color ?? AppColors.warn,
            backgroundColor: t.colorScheme.surfaceContainerHighest,
          ),
        ),
      ]),
    );
  }
}

Future<void> openExpense(BuildContext context, WarehouseStore store, Expense? e) =>
    showDialog(context: context, builder: (_) => _ExpenseForm(store: store, e: e));

class _ExpenseForm extends StatefulWidget {
  const _ExpenseForm({required this.store, this.e});
  final WarehouseStore store;
  final Expense? e;

  @override
  State<_ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<_ExpenseForm> {
  late String _date = widget.e?.date ?? todayIso();
  late String _cat = widget.e?.category ?? 'Rent';
  late final _amount = TextEditingController(text: widget.e?.amount.round().toString());
  late final _note = TextEditingController(text: widget.e?.note);
  final _newCat = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final cats = widget.store.expenseCategories;
    return AlertDialog(
      title: Text(widget.e == null ? 'Add expense' : 'Edit expense'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
              controller: _amount,
              autofocus: widget.e == null,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount (IQD)'),
            ),
            const SizedBox(height: 12),
            DatePickField(label: 'Date', value: _date, onChanged: (d) => setState(() => _date = d ?? _date)),
            const SizedBox(height: 14),
            const Text('What was it for?'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in cats)
                ChoiceChip(
                  avatar: Icon(categoryIcon(c), size: 18),
                  label: Text(c),
                  selected: _cat == c,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _cat = c),
                ),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: _newCat,
              decoration: const InputDecoration(labelText: 'Or type a new category'),
              onChanged: (v) => setState(() => _cat = v.trim().isEmpty ? (cats.first) : v.trim()),
            ),
            const SizedBox(height: 12),
            TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
          ]),
        ),
      ),
      actions: [
        if (widget.e != null)
          TextButton(
            onPressed: () async {
              if (await confirm(context, 'Delete this expense?', '${fmtMoney(widget.e!.amount)} · ${widget.e!.category}')) {
                widget.store.deleteExpense(widget.e!.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text('Delete', style: TextStyle(color: AppColors.bad)),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final a = parseNum(_amount.text);
            if (a == null || a <= 0) return toast(context, 'Enter the amount.');
            final note = _note.text.trim();
            widget.store.saveExpense(Expense(
              id: widget.e?.id ?? widget.store.newId('e'),
              date: _date,
              category: _cat,
              amount: a,
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
