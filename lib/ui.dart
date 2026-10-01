import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import 'models.dart';

final _qtyFmt = intl.NumberFormat('#,##0.##', 'en');
final _moneyFmt = intl.NumberFormat('#,##0', 'en');

String fmtQty(num q) => _qtyFmt.format(q);
String fmtMoney(num m) => '${_moneyFmt.format(m)} IQD';
String fmtDate(String? iso) {
  if (iso == null) return '—';
  final d = DateTime.tryParse(iso);
  return d == null ? iso : intl.DateFormat('d MMM yyyy').format(d);
}

String isoDate(DateTime d) => intl.DateFormat('yyyy-MM-dd').format(d);
String todayIso() => isoDate(DateTime.now());

/// Arabic text (item and department names) should read right-to-left even in the English UI.
TextDirection dirOf(String s) =>
    intl.Bidi.detectRtlDirectionality(s) ? TextDirection.rtl : TextDirection.ltr;

/// Text that picks its own direction, for user-entered names.
class NameText extends StatelessWidget {
  const NameText(this.text, {super.key, this.style, this.maxLines = 1});
  final String text;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Text(text,
      textDirection: dirOf(text), style: style, maxLines: maxLines, overflow: TextOverflow.ellipsis);
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final StockStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      StockStatus.inStock => ('In stock', Colors.green),
      StockStatus.low => ('Low', Colors.orange),
      StockStatus.out => ('Out', Colors.red),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color.shade800, fontWeight: FontWeight.w600, fontSize: 13)),
    );
  }
}

Future<bool> confirm(BuildContext context, String title, String message, {String action = 'Delete'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(action)),
        ],
      ),
    ) ??
    false;

void toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

/// Big search field used at the top of list screens.
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.onChanged, this.hint = 'Search'});
  final ValueChanged<String> onChanged;
  final String hint;

  @override
  Widget build(BuildContext context) => TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
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
