import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models.dart';
import '../pdf.dart';
import '../shell.dart';
import '../store.dart';
import '../theme.dart';
import '../ui.dart';
import 'send_file.dart';

/// Make barcode labels for items: pick items, choose barcode or QR, and print or send the sheet.
/// Each label carries the item's own code, which the scanner finds when issuing or counting.
class LabelsScreen extends StatefulWidget {
  const LabelsScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  State<LabelsScreen> createState() => _LabelsScreenState();
}

class _LabelsScreenState extends State<LabelsScreen> {
  final Set<String> _picked = {};
  String _q = '';
  bool _qr = false;
  int _copies = 1;

  List<Item> get _items => [for (final i in widget.store.items) if (i.active) i]..sort((a, b) => a.name.compareTo(b.name));

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = [for (final i in _items) if (q.isEmpty || i.name.toLowerCase().contains(q) || i.id.toLowerCase().contains(q)) i];
    final chosen = [for (final i in _items) if (_picked.contains(i.id)) i];
    return Scaffold(
      appBar: HeaderBar(title: Text(tx('Barcode labels', 'ملصقات الباركود')), bottom: SubNav.bar(context)),
      floatingActionButton: chosen.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => showPdfSheet(context,
                  name: 'Labels',
                  make: () => buildLabelsPdf(widget.store, chosen, qr: _qr, copies: _copies),
                  print: () => shareLabelsPdf(widget.store, chosen, qr: _qr, copies: _copies)),
              icon: const Icon(Icons.print_outlined),
              label: Text(tx('Make ${chosen.length * _copies} labels', 'إنشاء ${chosen.length * _copies} ملصق')),
            ),
      body: CardList(
        empty: tx('No items found.', 'لا توجد مواد.'),
        header: [
          SearchField(onChanged: (v) => setState(() => _q = v), hint: tx('Item name or code', 'اسم المادة أو الرمز')),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, icon: const Icon(Icons.view_week_outlined), label: Text(tx('Barcode', 'باركود'))),
                ButtonSegment(value: true, icon: const Icon(Icons.qr_code_2), label: Text(tx('QR code', 'رمز QR'))),
              ],
              selected: {_qr},
              onSelectionChanged: (v) => setState(() => _qr = v.first),
            ),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text(tx('Copies of each', 'نسخ لكل مادة')),
              IconButton(onPressed: _copies > 1 ? () => setState(() => _copies--) : null, icon: const Icon(Icons.remove_circle_outline)),
              Text('$_copies', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              IconButton(onPressed: _copies < 30 ? () => setState(() => _copies++) : null, icon: const Icon(Icons.add_circle_outline)),
            ]),
            TextButton(
              onPressed: () => setState(() => list.every((i) => _picked.contains(i.id))
                  ? _picked.removeAll([for (final i in list) i.id])
                  : _picked.addAll([for (final i in list) i.id])),
              child: Text(list.isNotEmpty && list.every((i) => _picked.contains(i.id)) ? tx('Clear these', 'إلغاء تحديدها') : tx('Pick all shown', 'تحديد كل المعروض')),
            ),
            TextButton(
              onPressed: () => setState(() => _picked.addAll([for (final i in _items) if ((i.barcode ?? '').isEmpty) i.id])),
              child: Text(tx('Pick items with no barcode', 'تحديد المواد بلا باركود')),
            ),
          ]),
        ],
        itemCount: list.length,
        itemBuilder: (_, k) {
          final i = list[k];
          return CheckboxListTile(
            value: _picked.contains(i.id),
            onChanged: (v) => setState(() => v == true ? _picked.add(i.id) : _picked.remove(i.id)),
            title: NameText(i.name, style: const TextStyle(fontSize: 17)),
            subtitle: Text((i.barcode ?? '').isEmpty
                ? tx('${i.id} · label shows the code ${i.id}', '${i.id} · الملصق يحمل الرمز ${i.id}')
                : tx('${i.id} · box barcode ${i.barcode}', '${i.id} · باركود العلبة ${i.barcode}')),
          );
        },
      ),
    );
  }
}
