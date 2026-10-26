import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';
import '../shell.dart';
import '../store.dart';
import '../theme.dart';
import '../ui.dart';

/// Stock count of the main store (or the reserve store): one item at a time, then the shortfall is issued to departments.
class StockCountScreen extends StatefulWidget {
  const StockCountScreen({super.key, required this.store, this.reserve = false});
  final WarehouseStore store;
  final bool reserve;

  @override
  State<StockCountScreen> createState() => _StockCountScreenState();
}

class _StockCountScreenState extends State<StockCountScreen> {
  final _qty = TextEditingController();
  final _focus = FocusNode();
  int? _i;

  StockCount? get _count => widget.store.countOf(reserve: widget.reserve);

  /// The reserve count covers the items held in the reserve when it starts.
  List<Item> get _items {
    final s = widget.store;
    if (!widget.reserve) return [...s.activeItems]..sort((a, b) => a.id.compareTo(b.id));
    final ids = _count?.items ?? [for (final x in s.stockList) if (x.reserve != 0) x.item.id];
    return [for (final id in ids) ?s.item(id)]..sort((a, b) => a.id.compareTo(b.id));
  }

  num _inApp(String id) => widget.reserve ? widget.store.stock(id).reserve : widget.store.stock(id).qty;

  @override
  void dispose() {
    _qty.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _show(int i) {
    final items = _items;
    _i = i.clamp(0, items.length - 1);
    final done = _count?.counted[items[_i!].id];
    _qty.text = done == null ? '' : fmtQty(done).replaceAll(',', '');
    _focus.requestFocus();
  }

  void _save(num q) {
    final s = widget.store, items = _items;
    final c = _count!;
    c.counted[items[_i!].id] = q;
    s.setStockCount(c, reserve: widget.reserve);
    final next = [for (var k = _i! + 1; k < items.length; k++) k].where((k) => !c.counted.containsKey(items[k].id)).firstOrNull;
    setState(() => next == null ? _i = items.length : _show(next));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store, c = _count, items = _items, t = Theme.of(context), reserve = widget.reserve;
    final appBar = AppBar(title: Text(reserve ? tx('Reserve count', 'جرد الاحتياط') : tx('Stock count', 'الجرد')), bottom: SubNav.bar(context));
    if (c == null) {
      return Scaffold(
        appBar: appBar,
        body: PageBody(children: [
          EmptyState(
            icon: Icons.fact_check_outlined,
            title: reserve
                ? tx('Count the reserve store item by item', 'جرد مخزن الاحتياط مادة بمادة')
                : tx('Count the main store item by item', 'جرد المخزن الأساسي مادة بمادة'),
            message: reserve
                ? (items.isEmpty
                    ? tx('Nothing is in the reserve store yet, so there is nothing to count.', 'لا توجد مواد في مخزن الاحتياط بعد، فلا يوجد ما يُجرد.')
                    : tx(
                        'You type the quantity in the reserve for each of the ${items.length} items held there, one after another. You can stop and continue later. '
                            'At the end, whatever is missing is recorded as an emergency issue to the departments you choose.',
                        'تكتب الكمية الموجودة في الاحتياط لكل مادة من ${items.length} مادة موجودة فيه، واحدة بعد الأخرى. يمكنك التوقف والإكمال لاحقاً. '
                            'في النهاية يُسجَّل النقص صرفاً طارئاً للأقسام التي تختارها.'))
                : tx(
                'You type the quantity on the shelf for each of the ${items.length} items, one after another. You can stop and continue later. '
                    'At the end, whatever is missing is recorded as issued to the departments you choose.',
                'تكتب الكمية الموجودة على الرف لكل مادة من ${items.length} مادة، واحدة بعد الأخرى. يمكنك التوقف والإكمال لاحقاً. '
                    'في النهاية يُسجَّل النقص كمصروف للأقسام التي تختارها.'),
            action: FilledButton.icon(
              onPressed: items.isEmpty ? null : () => setState(() {
                s.setStockCount(StockCount(started: todayIso(), items: reserve ? [for (final i in items) i.id] : null), reserve: reserve);
                _show(0);
              }),
              icon: const Icon(Icons.play_arrow),
              label: Text(tx('Start count', 'بدء الجرد')),
            ),
          ),
        ]),
      );
    }

    if (_i == null) {
      final first = items.indexWhere((i) => !c.counted.containsKey(i.id));
      first < 0 ? _i = items.length : _show(first);
    }
    final done = c.counted.length;
    final finished = _i! >= items.length;
    final item = finished ? null : items[_i!];
    final expected = item == null ? 0 : _inApp(item.id);

    return Scaffold(
      appBar: appBar,
      body: PageBody(maxWidth: 640, children: [
        Row(children: [
          Expanded(
              child: Text(tx('$done of ${items.length} counted', 'تم جرد $done من ${items.length}'),
                  style: t.textTheme.titleMedium)),
          TextButton(
            onPressed: () async {
              if (await confirm(context, tx('Cancel this count?', 'إلغاء هذا الجرد؟'),
                  tx('The numbers typed so far are thrown away. Stock does not change.', 'ستُحذف الأعداد المكتوبة حتى الآن. لن يتغير المخزون.'))) {
                s.setStockCount(null, reserve: reserve);
                setState(() => _i = null);
              }
            },
            child: Text(tx('Cancel count', 'إلغاء الجرد')),
          ),
        ]),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: items.isEmpty ? 0 : done / items.length, minHeight: 8, borderRadius: BorderRadius.circular(4)),
        const SizedBox(height: 16),
        if (item != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(tx('Item ${_i! + 1} of ${items.length}', 'المادة ${_i! + 1} من ${items.length}'),
                    style: t.textTheme.labelLarge!.copyWith(color: t.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 6),
                NameText(item.name, style: t.textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w800)),
                Text('${item.id} · ${item.unit}'),
                const SizedBox(height: 12),
                Text(tx('In the app: ${fmtQty(expected)}', 'في التطبيق: ${fmtQty(expected)}'), style: t.textTheme.titleMedium),
                const SizedBox(height: 16),
                TextField(
                  controller: _qty,
                  focusNode: _focus,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: t.textTheme.headlineSmall,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => _next(),
                  decoration: InputDecoration(labelText: tx('Counted now', 'العدد الحالي'), border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 16),
                Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.spaceBetween, children: [
                  OutlinedButton.icon(
                    onPressed: _i! == 0 ? null : () => setState(() => _show(_i! - 1)),
                    icon: const Icon(Icons.arrow_back),
                    label: Text(tx('Previous', 'السابقة')),
                  ),
                  OutlinedButton(
                    onPressed: () => _save(expected),
                    child: Text(tx('Same as app', 'مطابق للتطبيق')),
                  ),
                  FilledButton.icon(
                    onPressed: _next,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(tx('Next', 'التالية')),
                  ),
                ]),
              ]),
            ),
          )
        else
          Card(
            child: ListTile(
              leading: const Icon(Icons.check_circle, color: AppColors.good),
              title: Text(tx('Every item has a count.', 'تم جرد كل المواد.')),
              subtitle: Text(tx('Review the differences and save.', 'راجع الفروقات واحفظ.')),
            ),
          ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: done == 0
              ? null
              : () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ListenableBuilder(listenable: s, builder: (_, _) => _CountReview(store: s, reserve: reserve)))),
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(tx('Finish and review differences', 'إنهاء ومراجعة الفروقات')),
        ),
        if (!finished && done > 0) ...[
          const SizedBox(height: 8),
          Text(tx('Items not counted are left as they are.', 'المواد غير المجرودة تبقى كما هي.'),
              style: t.textTheme.bodySmall, textAlign: TextAlign.center),
        ],
      ]),
    );
  }

  void _next() {
    final q = parseNum(_qty.text);
    if (q == null || q < 0) return toast(context, tx('Type the quantity counted.', 'اكتب العدد الموجود.'));
    _save(q);
  }
}

/// Differences between the count and the app; the shortfall is issued to the departments chosen here.
class _CountReview extends StatefulWidget {
  const _CountReview({required this.store, this.reserve = false});
  final WarehouseStore store;
  final bool reserve;

  @override
  State<_CountReview> createState() => _CountReviewState();
}

class _CountReviewState extends State<_CountReview> {
  final Map<String, String> _dept = {};
  String? _all;

  @override
  Widget build(BuildContext context) {
    final s = widget.store, reserve = widget.reserve, c = s.countOf(reserve: reserve), t = Theme.of(context);
    if (c == null) return const SizedBox();
    num inApp(String id) => reserve ? s.stock(id).reserve : s.stock(id).qty;
    final rows = [
      for (final e in c.counted.entries)
        if (s.item(e.key) != null && inApp(e.key) != e.value) (item: s.item(e.key)!, counted: e.value, diff: inApp(e.key) - e.value),
    ]..sort((a, b) => a.item.id.compareTo(b.item.id));
    final short = rows.where((r) => r.diff > 0).toList(), over = rows.where((r) => r.diff < 0).toList();
    String? deptOf(String id) => _dept[id] ?? _all;

    return Scaffold(
      appBar: AppBar(title: Text(tx('Count differences', 'فروقات الجرد'))),
      body: PageBody(maxWidth: 860, children: [
        Text(tx('${c.counted.length} items counted · ${short.length} short · ${over.length} over',
            'تم جرد ${c.counted.length} مادة · ${short.length} فيها نقص · ${over.length} فيها زيادة'),
            style: t.textTheme.titleMedium),
        if (short.isNotEmpty) ...[
          SectionTitle(reserve
              ? tx('Missing: emergency issue to departments', 'النقص: يُسجَّل صرفاً طارئاً للأقسام')
              : tx('Missing: issued to departments', 'النقص: يُسجَّل مصروفاً للأقسام')),
          Text(tx('Department for all', 'القسم للكل'), style: t.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in s.departments)
              ChoiceChip(
                label: NameText(d),
                selected: _all == d,
                showCheckmark: false,
                onSelected: (_) => setState(() {
                  _all = d;
                  _dept.clear();
                }),
              ),
          ]),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final r in short)
                ListTile(
                  title: NameText(r.item.name),
                  subtitle: Text(tx('App ${fmtQty(r.counted + r.diff)} · counted ${fmtQty(r.counted)}',
                      'التطبيق ${fmtQty(r.counted + r.diff)} · المجرود ${fmtQty(r.counted)}')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('-${fmtQty(r.diff)}', style: const TextStyle(color: AppColors.bad, fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: deptOf(r.item.id),
                      hint: Text(tx('Department', 'القسم')),
                      items: [for (final d in s.departments) DropdownMenuItem(value: d, child: NameText(d))],
                      onChanged: (v) => setState(() => _dept[r.item.id] = v!),
                    ),
                  ]),
                ),
            ]),
          ),
        ],
        if (over.isNotEmpty) ...[
          SectionTitle(reserve
              ? tx('Extra: added to the reserve', 'الزيادة: تُضاف إلى الاحتياط')
              : tx('Extra: added to stock', 'الزيادة: تُضاف إلى المخزون')),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final r in over)
                ListTile(
                  title: NameText(r.item.name),
                  subtitle: Text(tx('App ${fmtQty(r.counted + r.diff)} · counted ${fmtQty(r.counted)}',
                      'التطبيق ${fmtQty(r.counted + r.diff)} · المجرود ${fmtQty(r.counted)}')),
                  trailing: Text('+${fmtQty(-r.diff)}', style: const TextStyle(color: AppColors.good, fontWeight: FontWeight.w700, fontSize: 16)),
                ),
            ]),
          ),
        ],
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(tx('Every counted item matches the app.', 'كل المواد المجرودة مطابقة للتطبيق.')),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () async {
            final missing = short.where((r) => deptOf(r.item.id) == null);
            if (missing.isNotEmpty) {
              return toast(context, tx('Choose a department for every missing item.', 'اختر قسماً لكل مادة فيها نقص.'));
            }
            if (!await confirm(
                context,
                tx('Save the count?', 'حفظ الجرد؟'),
                tx('Missing items are issued to the chosen departments and extra items are added to stock.',
                    'يُسجَّل النقص مصروفاً للأقسام المختارة وتُضاف الزيادة إلى المخزون.'),
                action: tx('Save', 'حفظ'))) {
              return;
            }
            final made = s.finishStockCount({for (final r in short) r.item.id: deptOf(r.item.id)!},
                date: todayIso(), label: reserve ? tx('Reserve count', 'جرد الاحتياط') : tx('Stock count', 'جرد'), reserve: reserve);
            if (!context.mounted) return;
            Navigator.pop(context);
            toast(context, tx('Count saved: ${made.length} issue receipts made.', 'حُفظ الجرد: أُنشئ ${made.length} وصل صرف.'));
          },
          icon: const Icon(Icons.save_outlined),
          label: Text(tx('Save count', 'حفظ الجرد')),
        ),
      ]),
    );
  }
}
