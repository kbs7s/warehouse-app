import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';
import '../shell.dart';
import '../store.dart';
import '../ui.dart';
import 'receipt_screens.dart';

/// What one department took in a period.
class DeptUse {
  DeptUse(this.name);
  final String name;
  final Map<String, num> qty = {}; // item id -> quantity
  final List<Receipt> receipts = [];
  num get total => qty.values.fold<num>(0, (s, q) => s + q);
}

/// Every department's issues between two dates (both included), most items first.
List<DeptUse> departmentUse(WarehouseStore store, String from, String to) {
  final out = <String, DeptUse>{};
  for (final r in store.receipts) {
    final d = r.date;
    if (d == null || d.compareTo(from) < 0 || d.compareTo(to) > 0) continue;
    final name = (r.department?.trim().isEmpty ?? true) ? tx('No department', 'بدون قسم') : r.department!.trim();
    final u = out.putIfAbsent(name, () => DeptUse(name))..receipts.add(r);
    for (final l in r.lines) {
      u.qty[l.itemId] = (u.qty[l.itemId] ?? 0) + l.qty;
    }
  }
  return out.values.toList()..sort((a, b) => b.total.compareTo(a.total));
}

/// The dates a department report covers, picked with chips or a calendar.
class DateSpan {
  const DateSpan(this.from, this.to, [this.period]);
  final String from, to;
  final Period? period;

  factory DateSpan.of(Period p) {
    final (a, b) = p.range();
    return DateSpan(a, b, p);
  }

}

class _RangeChips extends StatelessWidget {
  const _RangeChips({required this.range, required this.onChanged});
  final DateSpan range;
  final ValueChanged<DateSpan> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final p in Period.values)
          ChoiceChip(
            label: Text(p.label),
            selected: range.period == p,
            showCheckmark: false,
            onSelected: (_) => onChanged(DateSpan.of(p)),
          ),
        ActionChip(
          avatar: const Icon(Icons.date_range, size: 18),
          label: Text(range.period == null ? '${fmtDate(range.from)} – ${fmtDate(range.to)}' : tx('Pick dates', 'اختر التواريخ')),
          onPressed: () async {
            final now = DateTime.now();
            final r = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2015),
              lastDate: DateTime(now.year + 1, 12, 31),
              initialDateRange: range.period == Period.allTime
                  ? null
                  : DateTimeRange(start: DateTime.parse(range.from), end: DateTime.parse(range.to)),
            );
            if (r != null) onChanged(DateSpan(isoDate(r.start), isoDate(r.end)));
          },
        ),
      ]);
}

/// Issue → By department: how much each department took, with a page per department.
class DepartmentsScreen extends StatefulWidget {
  const DepartmentsScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  State<DepartmentsScreen> createState() => _DepartmentsScreenState();
}

class _DepartmentsScreenState extends State<DepartmentsScreen> {
  DateSpan _range = DateSpan.of(Period.thisMonth);
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final t = Theme.of(context);
    final all = departmentUse(s, _range.from, _range.to);
    final q = _q.trim().toLowerCase();
    final list = [for (final d in all) if (q.isEmpty || d.name.toLowerCase().contains(q)) d];
    final max = all.isEmpty ? 1 : all.first.total;
    final issues = all.fold<int>(0, (n, d) => n + d.receipts.length);
    final items = {for (final d in all) ...d.qty.keys}.length;

    return Scaffold(
      appBar: AppBar(title: Text(tx('Departments', 'الأقسام')), bottom: SubNav.bar(context)),
      body: PageBody(children: [
        _RangeChips(range: _range, onChanged: (r) => setState(() => _range = r)),
        const SizedBox(height: 14),
        TileGrid(children: [
          MetricTile(label: tx('Departments', 'الأقسام'), value: '${all.length}', icon: Icons.apartment_outlined, hint: tx('that took supplies', 'استلمت مواد')),
          MetricTile(label: tx('Issues', 'وصولات الصرف'), value: '$issues', icon: Icons.receipt_long_outlined),
          MetricTile(label: tx('Different items', 'مواد مختلفة'), value: '$items', icon: Icons.inventory_2_outlined),
          MetricTile(label: tx('Pieces given', 'الكمية المصروفة'), value: fmtQty(all.fold<num>(0, (n, d) => n + d.total)), icon: Icons.outbox_outlined),
        ]),
        const SizedBox(height: 14),
        if (all.length > 5) ...[
          SearchField(onChanged: (v) => setState(() => _q = v), hint: tx('Find a department', 'ابحث عن قسم')),
          const SizedBox(height: 12),
        ],
        if (list.isEmpty)
          EmptyState(
            icon: Icons.apartment_outlined,
            title: tx('Nothing issued in these dates', 'لا يوجد صرف في هذه التواريخ'),
            message: tx('Pick other dates above, for example "This year".', 'اختر تواريخ أخرى في الأعلى، مثلاً "هذه السنة".'),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final (i, d) in list.indexed) ...[
                if (i > 0) const Divider(height: 1),
                InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => ListenableBuilder(
                          listenable: s, builder: (_, _) => DepartmentDetailScreen(store: s, name: d.name, range: _range)))),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                    child: Row(children: [
                      CircleAvatar(
                        backgroundColor: t.colorScheme.primaryContainer,
                        child: Text(d.name.characters.first, style: TextStyle(color: t.colorScheme.primary, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          NameText(d.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(
                              tx('${d.receipts.length} issues · ${d.qty.length} items · ${fmtQty(d.total)} pieces',
                                  '${d.receipts.length} وصل · ${d.qty.length} مادة · ${fmtQty(d.total)} قطعة'),
                              style: TextStyle(color: t.colorScheme.onSurfaceVariant, fontSize: 13)),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(value: d.total / max, minHeight: 6),
                          ),
                        ]),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right),
                    ]),
                  ),
                ),
              ],
            ]),
          ),
      ]),
    );
  }
}

/// One department: every item it took in the dates, most first, and its issues.
class DepartmentDetailScreen extends StatefulWidget {
  const DepartmentDetailScreen({super.key, required this.store, required this.name, required DateSpan range}) : _initial = range;
  final WarehouseStore store;
  final String name;
  final DateSpan _initial;

  @override
  State<DepartmentDetailScreen> createState() => _DepartmentDetailScreenState();
}

class _DepartmentDetailScreenState extends State<DepartmentDetailScreen> {
  late DateSpan _range = widget._initial;

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final t = Theme.of(context);
    final d = departmentUse(s, _range.from, _range.to).where((e) => e.name == widget.name).firstOrNull ?? DeptUse(widget.name);
    final rows = d.qty.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final max = rows.isEmpty ? 1 : rows.first.value;
    final receipts = [...d.receipts]..sort((a, b) => (b.date ?? '').compareTo(a.date ?? ''));

    return Scaffold(
      appBar: AppBar(title: NameText(widget.name)),
      body: PageBody(children: [
        _RangeChips(range: _range, onChanged: (r) => setState(() => _range = r)),
        const SizedBox(height: 14),
        TileGrid(children: [
          MetricTile(label: tx('Issues', 'وصولات الصرف'), value: '${d.receipts.length}', icon: Icons.receipt_long_outlined),
          MetricTile(label: tx('Different items', 'مواد مختلفة'), value: '${rows.length}', icon: Icons.inventory_2_outlined),
          MetricTile(label: tx('Pieces given', 'الكمية المصروفة'), value: fmtQty(d.total), icon: Icons.outbox_outlined),
        ]),
        SectionTitle(tx('Items taken', 'المواد المستلمة'), trailing: Text('${rows.length}')),
        if (rows.isEmpty)
          EmptyState(icon: Icons.inventory_2_outlined, title: tx('Nothing issued in these dates', 'لا يوجد صرف في هذه التواريخ'))
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final (i, e) in rows.indexed) ...[
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    SizedBox(
                        width: 28,
                        child: Text('${i + 1}', style: TextStyle(color: t.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600))),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        NameText(s.item(e.key)?.name ?? e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(value: e.value / max, minHeight: 5),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    Text('${fmtQty(e.value)} ${s.item(e.key)?.unit ?? ''}',
                        style: t.textTheme.titleSmall!.copyWith(fontWeight: FontWeight.w800)),
                  ]),
                ),
              ],
            ]),
          ),
        if (receipts.isNotEmpty) ...[
          SectionTitle(tx('Issues', 'وصولات الصرف'), trailing: Text('${receipts.length}')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final (i, r) in receipts.indexed) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  onTap: () => openReceipt(context, s, r),
                  leading: CircleAvatar(child: Text('${r.no}', style: const TextStyle(fontSize: 13))),
                  title: Text(fmtDate(r.date)),
                  subtitle: Text(tx('${r.lines.length} items${r.customer == null ? '' : ' · ${r.customer}'}',
                      '${r.lines.length} مادة${r.customer == null ? '' : ' · ${r.customer}'}')),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ],
            ]),
          ),
        ],
      ]),
    );
  }
}

/// Settings card: the list of departments to pick from when issuing.
class DepartmentsCard extends StatefulWidget {
  const DepartmentsCard({super.key, required this.store});
  final WarehouseStore store;

  @override
  State<DepartmentsCard> createState() => _DepartmentsCardState();
}

class _DepartmentsCardState extends State<DepartmentsCard> {
  final _add = TextEditingController();

  void _addDept() {
    final ok = widget.store.addDepartment(_add.text);
    if (!ok) {
      toast(context, tx('Type a new department name.', 'اكتب اسم قسم جديد.'));
      return;
    }
    _add.clear();
  }

  Future<void> _rename(String d) async {
    final c = TextEditingController(text: d);
    final to = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tx('Rename department', 'تغيير اسم القسم')),
        content: TextField(controller: c, autofocus: true, decoration: InputDecoration(labelText: tx('Name', 'الاسم'))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tx('Cancel', 'إلغاء'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(tx('Save', 'حفظ'))),
        ],
      ),
    );
    if (to != null && to.trim().isNotEmpty && to.trim() != d) {
      widget.store.renameDepartment(d, to);
      if (mounted) toast(context, tx('Renamed. Past issues now show the new name.', 'تم تغيير الاسم. الصرف السابق يظهر بالاسم الجديد.'));
    }
  }

  Future<void> _remove(String d) async {
    if (await confirm(context, tx('Remove $d?', 'إزالة $d؟'),
        tx('It will not be offered when issuing. Past issues to it are kept.', 'لن يظهر عند الصرف. الصرف السابق له يبقى محفوظاً.'),
        action: tx('Remove', 'إزالة'))) {
      widget.store.removeDepartment(d);
    }
  }

  @override
  Widget build(BuildContext context) {
    final depts = [...widget.store.departments]..sort();
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(tx('Departments', 'الأقسام'), style: t.textTheme.titleLarge)),
            Text('${depts.length}', style: t.textTheme.titleMedium),
          ]),
          const SizedBox(height: 6),
          Text(tx('These show as one-tap choices when you issue supplies.', 'تظهر كخيارات سريعة عند الصرف.'),
              style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _add,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addDept(),
                decoration: InputDecoration(labelText: tx('New department', 'قسم جديد'), prefixIcon: const Icon(Icons.apartment_outlined)),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(onPressed: _addDept, icon: const Icon(Icons.add), label: Text(tx('Add', 'إضافة'))),
          ]),
          const SizedBox(height: 12),
          if (depts.isEmpty)
            Text(tx('No departments yet.', 'لا توجد أقسام بعد.'))
          else
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in depts)
                InputChip(
                  label: NameText(d),
                  onPressed: () => _rename(d),
                  onDeleted: () => _remove(d),
                  deleteButtonTooltipMessage: tx('Remove', 'إزالة'),
                ),
            ]),
          if (depts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(tx('Tap a department to rename it.', 'اضغط على القسم لتغيير اسمه.'),
                style: TextStyle(color: t.colorScheme.onSurfaceVariant, fontSize: 12.5)),
          ],
        ]),
      ),
    );
  }
}
