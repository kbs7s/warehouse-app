import 'package:flutter/material.dart';

import '../expiry.dart';
import '../l10n.dart';
import '../models.dart';
import '../shell.dart';
import '../store.dart';
import '../theme.dart';
import '../ui.dart';
import 'item_picker.dart';

Color expiryColor(ExpiryLevel l) => switch (l) {
      ExpiryLevel.expired => AppColors.bad,
      ExpiryLevel.soon => AppColors.warn,
      ExpiryLevel.coming => AppColors.info,
      ExpiryLevel.later => AppColors.good,
    };

/// "Expired 3 days ago" / "40 days left", coloured by how close it is.
class ExpiryChip extends StatelessWidget {
  const ExpiryChip(this.e, {super.key});
  final ExpiryInfo e;

  @override
  Widget build(BuildContext context) {
    final c = expiryColor(e.level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
      child: Text(e.label, style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12.5)),
    );
  }
}

/// Adds an expiry date to an item, or edits/deletes [batch].
Future<void> editExpiry(BuildContext context, WarehouseStore store, String itemId, {ExpiryBatch? batch}) =>
    showDialog(context: context, builder: (_) => _ExpiryForm(store: store, itemId: itemId, batch: batch));

class _ExpiryForm extends StatefulWidget {
  const _ExpiryForm({required this.store, required this.itemId, this.batch});
  final WarehouseStore store;
  final String itemId;
  final ExpiryBatch? batch;

  @override
  State<_ExpiryForm> createState() => _ExpiryFormState();
}

class _ExpiryFormState extends State<_ExpiryForm> {
  late String? _date = widget.batch?.date;
  late final _qty = TextEditingController(text: widget.batch?.qty == null ? '' : fmtQty(widget.batch!.qty!).replaceAll(',', ''));
  late final _lot = TextEditingController(text: widget.batch?.lot);

  @override
  Widget build(BuildContext context) {
    final item = widget.store.item(widget.itemId);
    return AlertDialog(
      title: Text(widget.batch == null ? tx('Add expiry date', 'إضافة تاريخ انتهاء') : tx('Edit expiry date', 'تعديل تاريخ الانتهاء')),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (item != null) ...[NameText(item.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)), const SizedBox(height: 14)],
          InkWell(
            onTap: () async {
              final now = DateTime.now();
              final d = await showDatePicker(
                context: context,
                initialDate: DateTime.tryParse(_date ?? '') ?? DateTime(now.year, now.month + 6, now.day),
                firstDate: DateTime(2015),
                lastDate: DateTime(2100),
              );
              if (d != null) setState(() => _date = isoDate(d));
            },
            child: InputDecorator(
              decoration: InputDecoration(labelText: tx('Expiry date', 'تاريخ الانتهاء'), suffixIcon: const Icon(Icons.event)),
              child: Text(_date == null ? tx('Tap to choose', 'اضغط للاختيار') : fmtDate(_date)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _qty,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: tx('Quantity with this date (optional)', 'الكمية بهذا التاريخ (اختياري)'), suffixText: item?.unit),
          ),
          const SizedBox(height: 12),
          TextField(controller: _lot, decoration: InputDecoration(labelText: tx('Lot / batch number (optional)', 'رقم التشغيلة (اختياري)'))),
        ]),
      ),
      actions: [
        if (widget.batch != null)
          TextButton(
            onPressed: () {
              widget.store.saveExpiry(widget.itemId, null, replacing: widget.batch);
              Navigator.pop(context);
            },
            child: Text(tx('Delete', 'حذف'), style: const TextStyle(color: AppColors.bad)),
          ),
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tx('Cancel', 'إلغاء'))),
        FilledButton(
          onPressed: () {
            if (_date == null) return toast(context, tx('Choose the expiry date.', 'اختر تاريخ الانتهاء.'));
            final lot = _lot.text.trim();
            widget.store.saveExpiry(
              widget.itemId,
              ExpiryBatch(date: _date!, qty: parseNum(_qty.text), lot: lot.isEmpty ? null : lot),
              replacing: widget.batch,
            );
            Navigator.pop(context);
          },
          child: Text(tx('Save', 'حفظ')),
        ),
      ],
    );
  }
}

/// Every expiry date entered, soonest first, with filters.
class ExpiryScreen extends StatefulWidget {
  const ExpiryScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  State<ExpiryScreen> createState() => _ExpiryScreenState();
}

enum _Show { alerts, expired, all }

class _ExpiryScreenState extends State<ExpiryScreen> {
  _Show _show = _Show.alerts;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final t = Theme.of(context);
    final all = s.expiryList(all: true);
    final inStock = s.expiryList();
    final expired = [for (final e in inStock) if (e.level == ExpiryLevel.expired) e];
    final alerts = s.expiryAlerts;
    final soon = inStock.where((e) => e.level == ExpiryLevel.soon).length;
    final base = switch (_show) { _Show.alerts => alerts, _Show.expired => expired, _Show.all => all };
    final q = _q.trim().toLowerCase();
    final list = [for (final e in base) if (q.isEmpty || e.item.name.toLowerCase().contains(q) || e.item.id.toLowerCase().contains(q)) e];

    return Scaffold(
      appBar: AppBar(title: Text(tx('Expiry dates', 'تواريخ الانتهاء')), bottom: SubNav.bar(context)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final id = await pickItem(context, s);
          if (id != null && context.mounted) await editExpiry(context, s, id);
        },
        icon: const Icon(Icons.add),
        label: Text(tx('Add expiry date', 'إضافة تاريخ انتهاء')),
      ),
      body: PageBody(children: [
        TileGrid(children: [
          MetricTile(
              label: tx('Expired', 'منتهية'),
              value: '${expired.length}',
              icon: Icons.dangerous_outlined,
              color: expired.isEmpty ? null : AppColors.bad,
              hint: tx('Still in stock', 'ما زالت في المخزن')),
          MetricTile(
              label: tx('Within 30 days', 'خلال 30 يوماً'),
              value: '$soon',
              icon: Icons.hourglass_bottom,
              color: soon == 0 ? null : AppColors.warn),
          MetricTile(
              label: tx('Within ${s.expiryWarnDays} days', 'خلال ${s.expiryWarnDays} يوماً'),
              value: '${alerts.length}',
              icon: Icons.notifications_active_outlined,
              hint: tx('Including expired', 'مع المنتهية')),
          MetricTile(
              label: tx('Dates entered', 'تواريخ مُدخلة'),
              value: '${all.length}',
              icon: Icons.event_note_outlined,
              hint: tx('${s.items.where((i) => i.expiries.isNotEmpty).length} items', '${s.items.where((i) => i.expiries.isNotEmpty).length} مادة')),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final (v, label) in [
            (_Show.alerts, tx('Needs attention', 'تحتاج انتباه')),
            (_Show.expired, tx('Expired', 'منتهية')),
            (_Show.all, tx('All dates', 'كل التواريخ')),
          ])
            ChoiceChip(label: Text(label), selected: _show == v, showCheckmark: false, onSelected: (_) => setState(() => _show = v)),
          SizedBox(width: 280, child: SearchField(onChanged: (v) => setState(() => _q = v))),
        ]),
        const SizedBox(height: 12),
        if (list.isEmpty)
          EmptyState(
            icon: Icons.event_available,
            title: all.isEmpty
                ? tx('No expiry dates yet', 'لا توجد تواريخ انتهاء بعد')
                : tx('Nothing expires within ${s.expiryWarnDays} days', 'لا شيء ينتهي خلال ${s.expiryWarnDays} يوماً'),
            message: all.isEmpty
                ? tx('Tap "Add expiry date", or open an item and add its dates. The app warns you before they expire.',
                    'اضغط "إضافة تاريخ انتهاء" أو افتح مادة وأضف تواريخها. سينبهك التطبيق قبل انتهائها.')
                : null,
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (final (i, e) in list.indexed) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  onTap: () => editExpiry(context, s, e.item.id, batch: e.batch),
                  leading: CircleAvatar(
                    backgroundColor: expiryColor(e.level).withValues(alpha: .12),
                    child: Icon(e.level == ExpiryLevel.expired ? Icons.dangerous_outlined : Icons.event, color: expiryColor(e.level), size: 20),
                  ),
                  title: NameText(e.item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${e.item.id} · ${batchLine(e.batch, e.item.unit)}',
                      style: t.textTheme.bodySmall!.copyWith(color: t.colorScheme.onSurfaceVariant)),
                  trailing: ExpiryChip(e),
                ),
              ],
            ]),
          ),
      ]),
    );
  }
}

/// The expiry dates block on an item's page.
class ItemExpirySection extends StatelessWidget {
  const ItemExpirySection({super.key, required this.store, required this.item});
  final WarehouseStore store;
  final Item item;

  @override
  Widget build(BuildContext context) {
    final list = [for (final e in store.expiryList(all: true)) if (e.item.id == item.id) e];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle(
        tx('Expiry dates', 'تواريخ الانتهاء'),
        trailing: TextButton.icon(
          onPressed: () => editExpiry(context, store, item.id),
          icon: const Icon(Icons.add, size: 18),
          label: Text(tx('Add', 'إضافة')),
        ),
      ),
      Card(
        clipBehavior: Clip.antiAlias,
        child: list.isEmpty
            ? ListTile(
                leading: const Icon(Icons.event_outlined),
                title: Text(tx('No expiry dates entered.', 'لا توجد تواريخ انتهاء.')),
                subtitle: Text(tx('Add the dates on the boxes to get a warning before they expire.', 'أضف التواريخ المكتوبة على العلب لتصلك تنبيهات قبل انتهائها.')),
                onTap: () => editExpiry(context, store, item.id),
              )
            : Column(children: [
                for (final (i, e) in list.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    onTap: () => editExpiry(context, store, item.id, batch: e.batch),
                    leading: Icon(e.level == ExpiryLevel.expired ? Icons.dangerous_outlined : Icons.event, color: expiryColor(e.level)),
                    title: Text(batchLine(e.batch, item.unit), style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: ExpiryChip(e),
                  ),
                ],
              ]),
      ),
    ]);
  }
}
