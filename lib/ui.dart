import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import 'l10n.dart';
import 'models.dart';
import 'theme.dart';

final _qtyFmt = intl.NumberFormat('#,##0.##', 'en');
final _moneyFmt = intl.NumberFormat('#,##0', 'en');

// In Arabic a left-to-right mark keeps the minus sign in front of the digits ("-14", not "14-").
String _ltr(num v, String s) => isAr && v < 0 ? '\u2066$s\u2069' : s;

String fmtQty(num q) => _ltr(q, _qtyFmt.format(q));
String get currency => tx('IQD', 'د.ع');
String fmtMoney(num m) => '${_ltr(m, _moneyFmt.format(m == 0 ? 0 : m))} $currency'; // never "-0"
String fmtDate(String? iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  return isAr ? '${d.day} ${arMonths[d.month - 1]} ${d.year}' : intl.DateFormat('d MMM yyyy').format(d);
}

/// "10/2026": month number and year only, for month and year pages.
String fmtMonth(String iso) => '${int.parse(iso.substring(5, 7))}/${iso.substring(0, 4)}';
String isoDate(DateTime d) => intl.DateFormat('yyyy-MM-dd').format(d);
String todayIso() => isoDate(DateTime.now());

/// Arabic text (item and department names) should read right-to-left even in the English UI.
TextDirection dirOf(String s) =>
    intl.Bidi.detectRtlDirectionality(s) ? TextDirection.rtl : TextDirection.ltr;

/// Text that picks its own direction, for user-entered names.
class NameText extends StatelessWidget {
  const NameText(this.text, {super.key, this.style, this.maxLines = 1, this.textAlign});
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextAlign? textAlign;

  // Aligned to the start of the interface (left in English, right in Arabic) whatever the name's
  // own direction, so mixed Arabic and English names line up.
  @override
  Widget build(BuildContext context) => Text(text,
      textDirection: dirOf(text),
      textAlign: textAlign ?? (Directionality.of(context) == TextDirection.rtl ? TextAlign.right : TextAlign.left),
      style: style,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis);
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final StockStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      StockStatus.inStock => (tx('In stock', 'متوفر'), Colors.green),
      StockStatus.low => (tx('Low', 'منخفض'), Colors.orange),
      StockStatus.out => (tx('Out', 'نفد'), Colors.red),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color.shade800, fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }
}

Future<bool> confirm(BuildContext context, String title, String message, {String? action}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tx('Cancel', 'إلغاء'))),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action ?? tx('Delete', 'حذف'))),
        ],
      ),
    ) ??
    false;

void toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

/// Big search field used at the top of list screens.
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.onChanged, this.hint});
  final ValueChanged<String> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) => TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint ?? tx('Search', 'بحث'),
          prefixIcon: const Icon(Icons.search),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );
}

/// Parses a quantity typed with Latin or Arabic-Indic digits.
num? parseNum(String s) {
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  final t = s.trim().split('').map((c) => arabic.contains(c) ? arabic.indexOf(c).toString() : c).join();
  return num.tryParse(t.replaceAll(',', '').replaceAll('٫', '.'));
}

/// Compact money for tiles: 1,250,000 -> "1.25M IQD".
String fmtMoneyShort(num m) {
  final a = m.abs();
  final sign = m < 0 ? '−' : '';
  final c = currency;
  String n(String digits) => _ltr(m, '$sign$digits');
  if (a >= 1e9) return '${n((a / 1e9).toStringAsFixed(2))}${tx('B', ' مليار')} $c';
  if (a >= 1e6) return '${n((a / 1e6).toStringAsFixed(a >= 1e8 ? 0 : 2))}${tx('M', ' مليون')} $c';
  if (a >= 1e4) return '${n((a / 1e3).toStringAsFixed(0))}${tx('K', ' ألف')} $c';
  return '${n(_moneyFmt.format(a))} $c';
}

bool isPhone(BuildContext context) => MediaQuery.sizeOf(context).width < 640;

/// A date range the dashboard and reports can be switched between.
enum Period { thisMonth, lastMonth, thisYear, allTime }

extension PeriodX on Period {
  String get label => switch (this) {
        Period.thisMonth => tx('This month', 'هذا الشهر'),
        Period.lastMonth => tx('Last month', 'الشهر الماضي'),
        Period.thisYear => tx('This year', 'هذه السنة'),
        Period.allTime => tx('All time', 'كل الوقت'),
      };

  (String, String) range([DateTime? now]) {
    final n = now ?? DateTime.now();
    return switch (this) {
      Period.thisMonth => (isoDate(DateTime(n.year, n.month)), isoDate(DateTime(n.year, n.month + 1, 0))),
      Period.lastMonth => (isoDate(DateTime(n.year, n.month - 1)), isoDate(DateTime(n.year, n.month, 0))),
      Period.thisYear => (isoDate(DateTime(n.year)), isoDate(DateTime(n.year, 12, 31))),
      Period.allTime => ('0000-01-01', '9999-12-31'),
    };
  }
}

/// Centered, width-limited page body with comfortable side padding on every screen size.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.maxWidth = 1100, this.bottomPad = 96});
  final List<Widget> children;
  final double maxWidth;
  final double bottomPad;

  @override
  Widget build(BuildContext context) {
    final pad = isPhone(context) ? 16.0 : 24.0;
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, 8, pad, bottomPad),
      children: [
        for (final c in children)
          Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: SizedBox(width: double.infinity, child: c))),
      ],
    );
  }
}

/// Big number with a label, used on the home screen and reports.
class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.label, required this.value, this.hint, this.color, this.icon, this.onTap});
  final String label;
  final String value;
  final String? hint;
  final Color? color;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: color ?? t.colorScheme.primary),
                const SizedBox(width: 6),
              ],
              Expanded(
                  child: Text(label,
                      style: t.textTheme.labelLarge!.copyWith(color: t.colorScheme.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value,
                  style: t.textTheme.headlineSmall!.copyWith(fontWeight: FontWeight.w800, color: color)),
            ),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(hint!,
                  style: t.textTheme.bodySmall!.copyWith(color: t.colorScheme.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Lays tiles out 2 per row on phones, 4 on wider screens.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, this.wideColumns = 4});
  final List<Widget> children;
  final int wideColumns;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth < 520 ? 2 : (c.maxWidth < 860 ? (wideColumns > 3 ? 3 : wideColumns) : wideColumns);
        const gap = 12.0;
        final w = (c.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(spacing: gap, runSpacing: gap, children: [
          for (final ch in children) SizedBox(width: w, child: ch),
        ]);
      });
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Row(children: [
          Expanded(
              child: Text(text, style: Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w700))),
          ?trailing,
        ]),
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(message!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      );
}

/// Simple grouped bar chart (e.g. sales vs profit per month), drawn without a chart package.
class BarChart extends StatelessWidget {
  const BarChart({super.key, required this.labels, required this.series, this.height = 180});
  final List<String> labels;
  final List<({String name, Color color, List<num> values})> series;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final maxV = series.expand((s) => s.values).fold<num>(0, (m, v) => v.abs() > m ? v.abs() : m);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 16, children: [
        for (final s in series)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 6),
            Text(s.name, style: t.textTheme.bodySmall),
          ]),
        if (series.any((s) => s.values.any((v) => v < 0)))
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: AppColors.bad, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 6),
            Text(tx('Loss', 'خسارة'), style: t.textTheme.bodySmall),
          ]),
      ]),
      const SizedBox(height: 12),
      SizedBox(
        height: height,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Expanded(
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (final s in series)
                      Tooltip(
                        message: '${s.name}: ${fmtMoney(s.values[i])}',
                        child: Container(
                          width: 10,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          height: maxV == 0 ? 0 : (height - 28) * (s.values[i].abs() / maxV),
                          decoration: BoxDecoration(
                            color: s.values[i] < 0 ? AppColors.bad : s.color,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 6),
                Text(labels[i], style: t.textTheme.labelSmall!.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ]),
            ),
        ]),
      ),
    ]);
  }
}

/// A long list inside a rounded card, width-limited, with controls (filters, search) above it.
class CardList extends StatelessWidget {
  const CardList({super.key, required this.header, required this.itemCount, required this.itemBuilder, this.empty});
  final List<Widget> header;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final String? empty;

  @override
  Widget build(BuildContext context) {
    final pad = isPhone(context) ? 16.0 : 24.0;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, 4, pad, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            ...header,
            const SizedBox(height: 12),
            Expanded(
              child: itemCount == 0
                  ? EmptyState(icon: Icons.search_off, title: empty ?? tx('Nothing here yet.', 'لا يوجد شيء بعد.'))
                  : Card(
                      clipBehavior: Clip.antiAlias,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListView.separated(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: itemCount,
                        separatorBuilder: (_, _) => const Divider(height: 1, indent: 16, endIndent: 16),
                        itemBuilder: itemBuilder,
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}
