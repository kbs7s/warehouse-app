import 'package:flutter/material.dart';

import '../l10n.dart';
import '../pdf.dart';
import '../shell.dart';
import '../store.dart';
import '../theme.dart';
import '../ui.dart';
import 'departments_screen.dart';
import 'home_screen.dart' show departmentSpend;
import 'send_file.dart';

/// The Saturday a week starts on (the working week here runs Saturday to Friday).
DateTime weekStart(DateTime d) {
  return DateTime(d.year, d.month, d.day - (d.weekday + 1) % 7);
}

/// Saturday to Friday of the week that starts on [start], as ISO dates.
(String, String) weekRange(DateTime start) => (isoDate(start), isoDate(DateTime(start.year, start.month, start.day + 6)));

String _short(DateTime d) => '${d.day}/${d.month}';

/// "Weekly report 15/11 - 21/11/2026".
String weeklyTitle(DateTime start) {
  final end = DateTime(start.year, start.month, start.day + 6);
  final span = '${_short(start)} - ${_short(end)}/${end.year}';
  return tx('Weekly report $span', 'التقرير الأسبوعي $span');
}

/// Issue → Weekly report: what each department took this week (Saturday to Friday), compared
/// with the week before. Every member of the team sees it; costs show only to the owner.
class WeeklyReportScreen extends StatefulWidget {
  const WeeklyReportScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  State<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends State<WeeklyReportScreen> {
  late DateTime _start = weekStart(DateTime.now());

  bool get _isThisWeek => _start == weekStart(DateTime.now());

  void _move(int weeks) => setState(() => _start = DateTime(_start.year, _start.month, _start.day + 7 * weeks));

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final t = Theme.of(context);
    final owner = !(s.cloud?.isStaff ?? false);
    final (from, to) = weekRange(_start);
    final (pFrom, pTo) = weekRange(DateTime(_start.year, _start.month, _start.day - 7));
    final all = departmentUse(s, from, to);
    final before = {for (final d in departmentUse(s, pFrom, pTo)) d.name: d.total};
    final spend = owner ? departmentSpend(s, from, to) : const <String, num>{};
    final max = all.isEmpty ? 1 : all.first.total;
    final pieces = all.fold<num>(0, (n, d) => n + d.total);
    final lastPieces = before.values.fold<num>(0, (n, q) => n + q);
    final issues = all.fold<int>(0, (n, d) => n + d.receipts.length);
    final title = weeklyTitle(_start);

    String change(num now, num was) {
      if (was == 0) return now == 0 ? '' : tx('new this week', 'جديد هذا الأسبوع');
      final p = ((now - was) / was * 100).round();
      if (p == 0) return tx('same as last week', 'مثل الأسبوع الماضي');
      return p > 0 ? tx('$p% more than last week', 'أكثر بـ $p% من الأسبوع الماضي') : tx('${-p}% less than last week', 'أقل بـ ${-p}% من الأسبوع الماضي');
    }

    return Scaffold(
      appBar: HeaderBar(title: Text(tx('Weekly report', 'التقرير الأسبوعي')), bottom: SubNav.bar(context), actions: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 8),
          child: TextButton.icon(
            onPressed: all.isEmpty
                ? null
                : () => showPdfSheet(context,
                    name: title.replaceAll('/', '-'),
                    make: () => buildDepartmentsPdf(s, from, to, title),
                    print: () => shareDepartmentsPdf(s, from, to, title)),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: Text(tx('Report PDF', 'تقرير PDF')),
          ),
        ),
      ]),
      body: PageBody(children: [
        // Week picker: previous / this week / next.
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(children: [
              IconButton(
                tooltip: tx('Previous week', 'الأسبوع السابق'),
                onPressed: () => _move(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Column(children: [
                  Text(_isThisWeek ? tx('This week', 'هذا الأسبوع') : tx('Week', 'الأسبوع'),
                      style: TextStyle(color: t.colorScheme.onSurfaceVariant, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text('${fmtDate(from)} – ${fmtDate(to)}',
                      textAlign: TextAlign.center, style: t.textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w800)),
                ]),
              ),
              if (!_isThisWeek)
                TextButton(onPressed: () => setState(() => _start = weekStart(DateTime.now())), child: Text(tx('This week', 'هذا الأسبوع'))),
              IconButton(
                tooltip: tx('Next week', 'الأسبوع التالي'),
                onPressed: _isThisWeek ? null : () => _move(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 14),
        TileGrid(children: [
          MetricTile(label: tx('Departments', 'الأقسام'), value: '${all.length}', icon: Icons.apartment_outlined, hint: tx('that took supplies', 'استلمت مواد')),
          MetricTile(label: tx('Issues', 'وصولات الصرف'), value: '$issues', icon: Icons.receipt_long_outlined),
          MetricTile(
              label: tx('Pieces given', 'الكمية المصروفة'),
              value: fmtQty(pieces),
              icon: Icons.outbox_outlined,
              hint: change(pieces, lastPieces).isEmpty ? null : change(pieces, lastPieces)),
          if (owner)
            MetricTile(
                label: tx('Cost', 'الكلفة'),
                value: fmtMoneyShort(spend.values.fold<num>(0, (a, b) => a + b)),
                icon: Icons.payments_outlined,
                hint: tx('seen by you only', 'تظهر لك فقط')),
        ]),
        SectionTitle(tx('Each department', 'صرفيات كل قسم'), trailing: Text('${all.length}')),
        if (all.isEmpty)
          EmptyState(
            icon: Icons.event_busy_outlined,
            title: tx('Nothing issued this week', 'لا يوجد صرف في هذا الأسبوع'),
            message: tx('Use the arrows above to see another week.', 'استخدم الأسهم في الأعلى لرؤية أسبوع آخر.'),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final (i, d) in all.indexed) ...[
                if (i > 0) const Divider(height: 1),
                Theme(
                  data: t.copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    key: PageStorageKey('week-$from-${d.name}'),
                    tilePadding: const EdgeInsetsDirectional.fromSTEB(16, 6, 12, 6),
                    childrenPadding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
                    leading: CircleAvatar(
                      backgroundColor: t.colorScheme.primaryContainer,
                      child: Text(d.name.characters.first, style: TextStyle(color: t.colorScheme.primary, fontWeight: FontWeight.w800)),
                    ),
                    title: NameText(d.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const SizedBox(height: 2),
                      Text(
                          [
                            tx('${d.receipts.length} issues · ${d.qty.length} items · ${fmtQty(d.total)} pieces',
                                '${d.receipts.length} وصل · ${d.qty.length} مادة · ${fmtQty(d.total)} قطعة'),
                            if (owner && (spend[d.name] ?? 0) > 0) fmtMoney(spend[d.name]!),
                          ].join(' · '),
                          style: TextStyle(color: t.colorScheme.onSurfaceVariant, fontSize: 13)),
                      if (change(d.total, before[d.name] ?? 0).isNotEmpty)
                        Text(change(d.total, before[d.name] ?? 0),
                            style: TextStyle(color: t.colorScheme.onSurfaceVariant, fontSize: 12.5, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: d.total / max, minHeight: 6)),
                    ]),
                    children: [
                      for (final e in (d.qty.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(children: [
                            Expanded(child: NameText(s.item(e.key)?.name ?? e.key)),
                            const SizedBox(width: 12),
                            Text('${fmtQty(e.value)} ${s.item(e.key)?.unit ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          ]),
                        ),
                    ],
                  ),
                ),
              ],
            ]),
          ),
      ]),
    );
  }
}
