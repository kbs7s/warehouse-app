import 'package:flutter/material.dart';

import '../export.dart';
import '../l10n.dart';
import 'send_file.dart';
import '../pdf.dart';
import '../models.dart';
import '../month.dart';
import '../shell.dart';
import '../store.dart';
import '../theme.dart';
import '../ui.dart';
import 'month_screen.dart';
import 'purchase_screens.dart';
import 'receipt_screens.dart';

/// Asks for a month's hospital figures (operations, catheterizations, NICU and insurance
/// admissions). Every field may stay empty. Returns null when cancelled.
Future<Map<String, num>?> askMonthStats(BuildContext context, {required String title, Map<String, num> initial = const {}}) {
  final ctl = {for (final k in monthStatKeys) k.$1: TextEditingController(text: initial[k.$1] == null ? '' : fmtQty(initial[k.$1]!).replaceAll(',', ''))};
  return showDialog<Map<String, num>>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tx('Figures for $title', 'أرقام $title')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tx('Leave a box empty if you do not have the number yet. You can fill it in later.',
                'اترك الحقل فارغاً إذا لم يتوفر الرقم بعد. يمكنك ملؤه لاحقاً.')),
            const SizedBox(height: 12),
            MonthStatFields(controllers: ctl),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(tx('Cancel', 'إلغاء'))),
        FilledButton(onPressed: () => Navigator.pop(c, readMonthStats(ctl)), child: Text(tx('Save', 'حفظ'))),
      ],
    ),
  );
}

Map<String, num> readMonthStats(Map<String, TextEditingController> ctl) => {
      for (final e in ctl.entries)
        if (parseNum(e.value.text) != null) e.key: parseNum(e.value.text)!,
    };

/// The four number boxes, two per row when there is room.
class MonthStatFields extends StatelessWidget {
  const MonthStatFields({super.key, required this.controllers});
  final Map<String, TextEditingController> controllers;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, c) {
        final w = c.maxWidth < 360 ? c.maxWidth : (c.maxWidth - 12) / 2;
        return Wrap(spacing: 12, runSpacing: 12, children: [
          for (final k in monthStatKeys)
            SizedBox(
              width: w,
              child: TextField(
                controller: controllers[k.$1],
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: tx(k.$2, k.$3), prefixIcon: Icon(statIcon(k.$1), size: 20)),
              ),
            ),
        ]);
      });
}

IconData statIcon(String key) => switch (key) {
      'operations' => Icons.medical_services_outlined,
      'cath' => Icons.monitor_heart_outlined,
      'nicu' => Icons.child_friendly_outlined,
      _ => Icons.verified_user_outlined,
    };

/// A closed month's issues, purchases and moves. Months closed before the fresh start was added
/// kept none of their own, so those are found by date.
({List<Receipt> issues, List<Purchase> purchases, List<Transfer> moves}) monthRecords(WarehouseStore s, MonthClose m) {
  if (m.fresh) return (issues: m.issueList, purchases: m.purchaseList, moves: m.transferList);
  bool inside(String? d) => d != null && d.compareTo(m.from) >= 0 && d.compareTo(m.to) <= 0;
  return (
    issues: [for (final r in s.allReceipts) if (inside(r.date)) r],
    purchases: [for (final p in s.allPurchases) if (inside(p.date)) p],
    moves: [for (final t in s.allTransfers) if (inside(t.date)) t],
  );
}

/// Every closed month, newest first, grouped by year.
class MonthArchiveScreen extends StatelessWidget {
  const MonthArchiveScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final closes = store.monthCloses.reversed.toList();
    final years = <String, List<MonthClose>>{};
    for (final m in closes) {
      years.putIfAbsent(m.from.substring(0, 4), () => []).add(m);
    }
    return Scaffold(
      appBar: HeaderBar(title: Text(tx('Archive', 'الأرشيف')), bottom: SubNav.bar(context)),
      body: closes.isEmpty
          ? EmptyState(
              icon: Icons.inventory_outlined,
              title: tx('No closed months yet', 'لا توجد أشهر مغلقة بعد'),
              message: tx('When you close a month on the Month end page, it is kept here with its issues, purchases and departments.',
                  'عند إغلاق الشهر من صفحة نهاية الشهر يُحفظ هنا مع صرفياته ومشترياته وأقسامه.'),
            )
          : PageBody(maxWidth: 860, children: [
              for (final y in years.entries) ...[
                SectionTitle(y.key, trailing: Text(tx('${y.value.length} months', '${y.value.length} أشهر'))),
                _YearTotals(months: y.value),
                const SizedBox(height: 10),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    for (final (i, m) in y.value.indexed) ...[
                      if (i > 0) const Divider(height: 1),
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        leading: CircleAvatar(
                          backgroundColor: t.colorScheme.primaryContainer,
                          child: Text('${int.parse(m.from.substring(5, 7))}',
                              style: TextStyle(fontWeight: FontWeight.w800, color: t.colorScheme.onPrimaryContainer)),
                        ),
                        title: Text(monthName(m.from, m.to), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16.5)),
                        subtitle: Text(_monthLine(store, m)),
                        trailing: m.statsMissing
                            ? Chip(
                                visualDensity: VisualDensity.compact,
                                avatar: Icon(Icons.edit_note, size: 18, color: t.colorScheme.warning),
                                label: Text(tx('Figures to fill', 'أرقام ناقصة')),
                              )
                            : const Icon(Icons.chevron_right),
                        onTap: () => openClosedMonth(context, store, m),
                      ),
                    ],
                  ]),
                ),
              ],
            ]),
    );
  }
}

String _monthLine(WarehouseStore s, MonthClose m) {
  final r = monthRecords(s, m);
  return tx('${r.issues.length} issues · ${r.purchases.length} purchases · spent ${fmtQty(m.issued)} units',
      '${r.issues.length} وصل صرف · ${r.purchases.length} شراء · المصروف ${fmtQty(m.issued)} وحدة');
}

/// The year's operations, catheterizations and admissions added up.
class _YearTotals extends StatelessWidget {
  const _YearTotals({required this.months});
  final List<MonthClose> months;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final k in monthStatKeys)
        Chip(
          avatar: Icon(statIcon(k.$1), size: 18, color: t.colorScheme.primary),
          label: Text('${tx(k.$2, k.$3)}: ${fmtQty(months.fold<num>(0, (a, m) => a + (m.stats[k.$1] ?? 0)))}'),
        ),
    ]);
  }
}

void openClosedMonth(BuildContext context, WarehouseStore store, MonthClose m) => Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => ListenableBuilder(listenable: store, builder: (_, _) => ClosedMonthScreen(store: store, month: m))));

enum _Part { items, issues, purchases, departments, moves }

/// Everything about one closed month: its figures, items, issues, purchases, departments and moves.
class ClosedMonthScreen extends StatefulWidget {
  const ClosedMonthScreen({super.key, required this.store, required this.month});
  final WarehouseStore store;
  final MonthClose month;

  @override
  State<ClosedMonthScreen> createState() => _ClosedMonthScreenState();
}

class _ClosedMonthScreenState extends State<ClosedMonthScreen> {
  _Part _part = _Part.departments;

  WarehouseStore get s => widget.store;
  MonthClose get m => widget.month;

  Future<void> _export() async {
    final r = monthRecords(s, m);
    await exportMonthExcel(
      s,
      'month-${m.from.substring(0, 7)}.xlsx',
      monthSheets(s,
          title: monthName(m.from, m.to),
          from: m.from,
          to: m.to,
          rows: m.rows,
          stats: m.stats,
          issues: r.issues,
          purchases: r.purchases,
          moves: r.moves,
          reserveStart: m.reserveStart,
          reserveEnd: m.reserveEnd),
    );
  }

  Future<void> _editStats() async {
    final v = await askMonthStats(context, title: monthName(m.from, m.to), initial: m.stats);
    if (v != null) s.setMonthStats(m, v);
  }

  Future<void> _reopen() async {
    final title = monthName(m.from, m.to);
    final why = s.reopenBlocker();
    if (why != null) {
      if (why.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(tx('Cannot reopen $title', 'لا يمكن إعادة فتح $title')),
            content: Text(why),
            actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(tx('OK', 'حسناً')))],
          ),
        );
      }
      return;
    }
    if (await confirm(
        context,
        tx('Reopen $title?', 'إعادة فتح $title؟'),
        tx('Its issues, purchases and moves go back to the open lists, and the items get back the stock they started the month with.',
            'تعود صرفياته ومشترياته وعمليات النقل إلى القوائم المفتوحة، ويعود رصيد أول الشهر كما كان.'),
        action: tx('Reopen', 'إعادة فتح'))) {
      s.reopenLastMonth();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final title = monthName(m.from, m.to);
    final r = monthRecords(s, m);
    final isLast = s.monthCloses.isNotEmpty && identical(s.monthCloses.last, m);
    final moved = m.rows.where(rowMoved).toList();
    return Scaffold(
      appBar: HeaderBar(
        title: Text(title),
        actions: [
          IconButton(
            tooltip: tx('Month report PDF', 'تقرير الشهر PDF'),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => showPdfSheet(context,
                name: 'Month-report-${m.from.substring(0, 7)}',
                make: () => buildMonthReportPdf(s,
                    title: title, from: m.from, to: m.to, rows: m.rows, stats: m.stats, issues: r.issues, purchases: r.purchases)),
          ),
          IconButton(tooltip: tx('Export month to Excel', 'تصدير الشهر إلى إكسل'), icon: const Icon(Icons.table_view_outlined), onPressed: _export),
          if (isLast)
            PopupMenuButton<String>(
              tooltip: tx('More', 'المزيد'),
              onSelected: (_) => _reopen(),
              itemBuilder: (_) => [PopupMenuItem(value: 'reopen', child: Text(tx('Reopen this month', 'إعادة فتح هذا الشهر')))],
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: PageBody(children: [
        Text('${fmtDate(m.from)} – ${fmtDate(m.to)}', style: t.textTheme.bodyMedium!.copyWith(color: t.colorScheme.onSurfaceVariant)),
        SectionTitle(tx('Hospital figures', 'أرقام المستشفى'),
            trailing: TextButton.icon(
              onPressed: _editStats,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: Text(m.statsMissing ? tx('Fill in', 'إدخال') : tx('Edit', 'تعديل')),
            )),
        TileGrid(children: [
          for (final k in monthStatKeys)
            MetricTile(
              label: tx(k.$2, k.$3),
              value: m.stats[k.$1] == null ? '—' : fmtQty(m.stats[k.$1]!),
              icon: statIcon(k.$1),
              hint: m.stats[k.$1] == null ? tx('Not filled in yet', 'لم يُدخل بعد') : null,
              onTap: _editStats,
            ),
        ]),
        SectionTitle(tx('Store', 'المخزن')),
        TileGrid(children: [
          MetricTile(label: tx('Spent', 'المصروف'), value: fmtQty(m.issued), icon: Icons.outbox_outlined, hint: tx('Units', 'وحدة')),
          MetricTile(label: tx('Received', 'الوارد'), value: fmtQty(m.received), icon: Icons.move_to_inbox_outlined, hint: tx('Units', 'وحدة')),
          MetricTile(label: tx('Issue receipts', 'وصولات الصرف'), value: '${r.issues.length}', icon: Icons.receipt_long_outlined),
          MetricTile(label: tx('Purchases', 'المشتريات'), value: '${r.purchases.length}', icon: Icons.shopping_cart_outlined),
        ]),
        const SizedBox(height: 18),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final (p, en, ar) in [
              (_Part.departments, 'Departments', 'الأقسام'),
              (_Part.issues, 'Issues', 'الصرفيات'),
              (_Part.purchases, 'Purchases', 'المشتريات'),
              (_Part.items, 'Items', 'المواد'),
              (_Part.moves, 'Moves', 'النقل'),
            ])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8),
                child: ChoiceChip(
                  label: Text(tx(en, ar)),
                  selected: _part == p,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _part = p),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        ...switch (_part) {
          _Part.items => [
              MonthTable(store: s, rows: [...moved, ...m.rows.where((r) => !rowMoved(r))], emptyText: tx('No items.', 'لا توجد مواد.')),
            ],
          _Part.issues => [_IssueList(store: s, issues: r.issues)],
          _Part.purchases => [_PurchaseList(store: s, purchases: r.purchases)],
          _Part.departments => [_DepartmentList(store: s, issues: r.issues)],
          _Part.moves => [_MoveList(store: s, moves: r.moves)],
        },
      ]),
    );
  }
}

Widget _emptyCard(String text) => Card(child: ListTile(leading: const Icon(Icons.inbox_outlined), title: Text(text)));

class _IssueList extends StatelessWidget {
  const _IssueList({required this.store, required this.issues});
  final WarehouseStore store;
  final List<Receipt> issues;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return _emptyCard(tx('No issues this month.', 'لا يوجد صرف هذا الشهر.'));
    final list = [...issues]..sort((a, b) => (b.date ?? '').compareTo(a.date ?? '') != 0 ? (b.date ?? '').compareTo(a.date ?? '') : b.no.compareTo(a.no));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (final (i, r) in list.indexed) ...[
          if (i > 0) const Divider(height: 1),
          ListTile(
            leading: CircleAvatar(child: Text('${r.no}', style: const TextStyle(fontSize: 13))),
            title: NameText(r.department ?? tx('No department', 'بدون قسم'), style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(tx('${fmtDate(r.date)} · ${r.lines.length} items', '${fmtDate(r.date)} · ${r.lines.length} مادة') +
                (r.fromReserve ? tx(' · from reserve', ' · من الاحتياط') : '')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openAnyReceipt(context, store, r),
          ),
        ],
      ]),
    );
  }
}

class _PurchaseList extends StatelessWidget {
  const _PurchaseList({required this.store, required this.purchases});
  final WarehouseStore store;
  final List<Purchase> purchases;

  @override
  Widget build(BuildContext context) {
    if (purchases.isEmpty) return _emptyCard(tx('No purchases this month.', 'لا توجد مشتريات هذا الشهر.'));
    final list = [...purchases]..sort((a, b) => (b.date ?? '').compareTo(a.date ?? ''));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (final (i, p) in list.indexed) ...[
          if (i > 0) const Divider(height: 1),
          ListTile(
            leading: CircleAvatar(child: Text('${p.no}', style: const TextStyle(fontSize: 13))),
            title: NameText(p.supplier ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(tx('${fmtDate(p.date)} · ${p.lines.length} items', '${fmtDate(p.date)} · ${p.lines.length} مادة') +
                (p.toReserve ? tx(' · into reserve', ' · إلى الاحتياط') : '')),
            trailing: Text(fmtMoney(p.total), style: const TextStyle(fontWeight: FontWeight.w700)),
            onTap: () => openAnyPurchase(context, store, p),
          ),
        ],
      ]),
    );
  }
}

class _DepartmentList extends StatelessWidget {
  const _DepartmentList({required this.store, required this.issues});
  final WarehouseStore store;
  final List<Receipt> issues;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) return _emptyCard(tx('No department took anything this month.', 'لم يُصرف لأي قسم هذا الشهر.'));
    final t = Theme.of(context);
    final qty = <String, Map<String, num>>{}, count = <String, int>{};
    for (final r in issues) {
      final d = (r.department?.trim().isEmpty ?? true) ? tx('No department', 'بدون قسم') : r.department!.trim();
      count[d] = (count[d] ?? 0) + 1;
      final m = qty.putIfAbsent(d, () => {});
      for (final l in r.lines) {
        m[l.itemId] = (m[l.itemId] ?? 0) + l.qty;
      }
    }
    num total(Map<String, num> m) => m.values.fold<num>(0, (a, b) => a + b);
    final depts = qty.keys.toList()..sort((a, b) => total(qty[b]!).compareTo(total(qty[a]!)));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (final (i, d) in depts.indexed) ...[
          if (i > 0) const Divider(height: 1),
          ExpansionTile(
            leading: CircleAvatar(
                backgroundColor: t.colorScheme.secondaryContainer,
                child: Icon(Icons.apartment_outlined, size: 20, color: t.colorScheme.onSecondaryContainer)),
            title: NameText(d, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(tx('${count[d]} issues · ${qty[d]!.length} items · ${fmtQty(total(qty[d]!))} pieces',
                '${count[d]} وصل · ${qty[d]!.length} مادة · ${fmtQty(total(qty[d]!))} قطعة')),
            children: [
              for (final e in (qty[d]!.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
                ListTile(
                  dense: true,
                  title: NameText(store.item(e.key)?.name ?? e.key),
                  trailing: Text('${fmtQty(e.value)} ${store.item(e.key)?.unit ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ],
      ]),
    );
  }
}

class _MoveList extends StatelessWidget {
  const _MoveList({required this.store, required this.moves});
  final WarehouseStore store;
  final List<Transfer> moves;

  @override
  Widget build(BuildContext context) {
    if (moves.isEmpty) return _emptyCard(tx('No moves between the stores this month.', 'لا يوجد نقل بين المخزنين هذا الشهر.'));
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (final tr in moves)
          ListTile(
            leading: Icon(tr.toReserve ? Icons.move_down : Icons.move_up, color: tr.toReserve ? AppColors.warn : AppColors.good),
            title: NameText(store.item(tr.itemId)?.name ?? tr.itemId),
            subtitle: Text('${fmtDate(tr.date)} · ${tr.toReserve ? tx('to reserve', 'إلى الاحتياط') : tx('back to main', 'إلى الأساسي')}'),
            trailing: Text(fmtQty(tr.qty), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
      ]),
    );
  }
}

/// Opens an issue: the editor while it is in the open month, a read-only page once its month is closed.
void openAnyReceipt(BuildContext context, WarehouseStore store, Receipt r) {
  if (store.receipts.any((x) => identical(x, r))) return openReceipt(context, store, r);
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => _KeptReceiptScreen(store: store, receipt: r)));
}

void openAnyPurchase(BuildContext context, WarehouseStore store, Purchase p) {
  if (store.purchases.any((x) => identical(x, p))) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PurchaseEditor(store: store, existing: p), fullscreenDialog: true));
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => _KeptPurchaseScreen(store: store, purchase: p)));
}

Widget _closedNote(BuildContext context) {
  final t = Theme.of(context);
  return Card(
    color: t.colorScheme.surfaceContainerHighest,
    child: ListTile(
      leading: const Icon(Icons.lock_outline),
      title: Text(tx('Kept with a closed month', 'محفوظ مع شهر مغلق')),
      subtitle: Text(tx('It can be viewed, sent and printed, but not changed.', 'يمكن عرضه وإرساله وطباعته، لكن لا يمكن تعديله.')),
    ),
  );
}

class _KeptReceiptScreen extends StatelessWidget {
  const _KeptReceiptScreen({required this.store, required this.receipt});
  final WarehouseStore store;
  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    final r = receipt;
    return Scaffold(
      appBar: HeaderBar(
        title: Text(tx('Issue #${r.no}', 'وصل صرف رقم ${r.no}')),
        actions: [
          IconButton(tooltip: tx('Send or print PDF', 'إرسال أو طباعة PDF'), icon: const Icon(Icons.ios_share), onPressed: () => sendReceipt(context, store, r)),
          const SizedBox(width: 8),
        ],
      ),
      body: PageBody(maxWidth: 760, children: [
        _closedNote(context),
        Card(
          child: Column(children: [
            ListTile(leading: const Icon(Icons.apartment_outlined), title: NameText(r.department ?? '—'), subtitle: Text(tx('Department', 'القسم'))),
            ListTile(leading: const Icon(Icons.event_outlined), title: Text(fmtDate(r.date)), subtitle: Text(tx('Date', 'التاريخ'))),
            if (r.customer != null)
              ListTile(leading: const Icon(Icons.person_outline), title: NameText(r.customer!), subtitle: Text(tx('Received by', 'المستلم'))),
            if (r.fromReserve)
              ListTile(leading: const Icon(Icons.emergency_outlined), title: Text(tx('From the reserve store', 'من مخزن الاحتياط'))),
            if (r.note != null) ListTile(leading: const Icon(Icons.notes_outlined), title: Text(r.note!)),
          ]),
        ),
        SectionTitle(tx('Items', 'المواد'), trailing: Text('${r.lines.length}')),
        Card(
          child: Column(children: [
            for (final l in r.lines)
              ListTile(
                title: NameText(store.item(l.itemId)?.name ?? l.itemId),
                subtitle: Text(l.itemId),
                trailing: Text('${fmtQty(l.qty)} ${store.item(l.itemId)?.unit ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _KeptPurchaseScreen extends StatelessWidget {
  const _KeptPurchaseScreen({required this.store, required this.purchase});
  final WarehouseStore store;
  final Purchase purchase;

  @override
  Widget build(BuildContext context) {
    final p = purchase;
    return Scaffold(
      appBar: HeaderBar(title: Text(tx('Purchase #${p.no}', 'شراء رقم ${p.no}'))),
      body: PageBody(maxWidth: 760, children: [
        _closedNote(context),
        Card(
          child: Column(children: [
            ListTile(leading: const Icon(Icons.local_shipping_outlined), title: NameText(p.supplier ?? '—'), subtitle: Text(tx('Supplier', 'المجهز'))),
            ListTile(leading: const Icon(Icons.event_outlined), title: Text(fmtDate(p.date)), subtitle: Text(tx('Date', 'التاريخ'))),
            if (p.ref != null) ListTile(leading: const Icon(Icons.tag), title: Text(p.ref!), subtitle: Text(tx("Supplier's bill no.", 'رقم قائمة المجهز'))),
            if (p.toReserve) ListTile(leading: const Icon(Icons.emergency_outlined), title: Text(tx('Into the reserve store', 'إلى مخزن الاحتياط'))),
            ListTile(leading: const Icon(Icons.payments_outlined), title: Text(fmtMoney(p.total)), subtitle: Text(tx('Total', 'المجموع'))),
          ]),
        ),
        SectionTitle(tx('Items', 'المواد'), trailing: Text('${p.lines.length}')),
        Card(
          child: Column(children: [
            for (final l in p.lines)
              ListTile(
                title: NameText(store.item(l.itemId)?.name ?? l.itemId),
                subtitle: Text([l.itemId, if (l.expiry != null) tx('expires ${fmtDate(l.expiry)}', 'ينتهي ${fmtDate(l.expiry)}')].join(' · ')),
                trailing: Text('${fmtQty(l.qty)} ${store.item(l.itemId)?.unit ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
      ]),
    );
  }
}
