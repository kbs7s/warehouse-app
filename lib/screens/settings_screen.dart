import 'dart:convert';

import 'package:flutter/material.dart';

import '../export.dart';
import '../l10n.dart';
import '../platform/files.dart';
import '../shell.dart';
import '../store.dart';
import '../theme.dart';
import '../ui.dart';
import 'cloud_screens.dart';
import 'departments_screen.dart';
import 'welcome_screen.dart' show LanguageChips;

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store, this.shell});
  final WarehouseStore store;
  final Shell? shell;

  Future<void> _backup(BuildContext context) async {
    final name = 'warehouse-backup-${todayIso()}.json';
    store.markBackedUp();
    await downloadFile(name, utf8.encode(jsonEncode(store.toJson())), 'application/json');
    if (context.mounted) toast(context, tx('Backup saved as $name. Keep it in Files or iCloud Drive.', 'حُفظت النسخة الاحتياطية باسم $name. احتفظ بها في Files أو iCloud Drive.'));
  }

  Future<void> _restore(BuildContext context) async {
    final text = await pickTextFile();
    if (text == null || !context.mounted) return;
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      if (!await confirm(context, tx('Restore this backup?', 'استرجاع هذه النسخة الاحتياطية؟'),
          tx('Everything in the app now will be replaced by the backup from ${j['savedAt'] ?? 'an unknown date'}.',
              'كل ما في التطبيق الآن سيُستبدل بالنسخة الاحتياطية بتاريخ ${j['savedAt'] ?? 'غير معروف'}.'),
          action: tx('Restore', 'استرجاع'))) {
        return;
      }
      store.applyJson(j);
      if (context.mounted) toast(context, tx('Backup restored.', 'تم استرجاع النسخة الاحتياطية.'));
    } catch (e) {
      if (context.mounted) toast(context, tx('Could not read that file: $e', 'تعذّرت قراءة الملف: $e'));
    }
  }

  Future<void> _erase(BuildContext context) async {
    if (!await confirm(context, tx('Erase all data on this device?', 'مسح كل البيانات على هذا الجهاز؟'),
        tx('Every item, invoice, client, purchase, expense and payment is deleted. Export a backup first if unsure.',
            'ستُحذف كل المواد والفواتير والزبائن والمشتريات والمصاريف والدفعات. صدّر نسخة احتياطية أولاً إذا لم تكن متأكداً.'),
        action: tx('Erase', 'مسح'))) {
      return;
    }
    final cloud = store.cloud;
    if (cloud != null && cloud.signedIn) {
      await cloud.signOut(); // the shared copy stays online for the team
    } else {
      await store.eraseAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = store.lastBackupAt == null ? null : DateTime.tryParse(store.lastBackupAt!);
    final days = last == null ? null : DateTime.now().difference(last).inDays;
    return Scaffold(
      appBar: AppBar(title: Text(tx('Backup & settings', 'النسخ الاحتياطي والإعدادات')), bottom: SubNav.bar(context)),
      body: PageBody(maxWidth: 860, children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(child: Text('Language / اللغة', style: Theme.of(context).textTheme.titleLarge)),
              LanguageChips(store: store),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        AppearanceCard(store: store),
        const SizedBox(height: 12),
        CloudCard(store: store),
        const SizedBox(height: 12),
        _BusinessCard(store: store),
        const SizedBox(height: 12),
        DepartmentsCard(store: store),
        if (shell != null) ...[
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(tx('Sales, clients and expenses', 'المبيعات والزبائن والمصاريف')),
              subtitle: Text(tx('Invoices to clients, running costs and profit.', 'فواتير الزبائن والمصاريف والأرباح.')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => shell!.go('Money'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tx('Expiry warnings', 'تنبيهات الانتهاء'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              Text(tx('Warn me this many days before an expiry date.', 'نبّهني قبل تاريخ الانتهاء بهذا العدد من الأيام.')),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final d in const [30, 60, 90, 180])
                  ChoiceChip(
                    label: Text(tx('$d days', '$d يوماً')),
                    selected: store.expiryWarnDays == d,
                    showCheckmark: false,
                    onSelected: (_) => store.setExpiryWarnDays(d),
                  ),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tx('Backup', 'النسخ الاحتياطي'), style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (store.cloud?.signedIn ?? false)
                Text(tx('Your data is shared online and saved on this device. A backup file each month is still a good idea.',
                    'بياناتك مشتركة أونلاين ومحفوظة على هذا الجهاز. يبقى من الجيد تصدير نسخة احتياطية كل شهر.'))
              else
              Text(tx(
                  'Your data is saved only on this device. Export a backup at least once a week and keep it in '
                      'Files or iCloud Drive, so nothing is lost if Safari data is cleared.',
                  'بياناتك محفوظة على هذا الجهاز فقط. صدّر نسخة احتياطية مرة في الأسبوع على الأقل واحفظها في '
                      'Files أو iCloud Drive، حتى لا يضيع شيء إذا مُسحت بيانات Safari.')),
              const SizedBox(height: 8),
              Text(
                  last == null
                      ? tx('No backup exported yet.', 'لم تُصدَّر أي نسخة احتياطية بعد.')
                      : tx('Last backup: ${fmtDate(store.lastBackupAt)} ($days days ago)',
                          'آخر نسخة احتياطية: ${fmtDate(store.lastBackupAt)} (قبل $days يوم)'),
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: days == null || days > 7 ? Colors.red : Colors.green)),
              const SizedBox(height: 16),
              Wrap(spacing: 12, runSpacing: 12, children: [
                FilledButton.icon(
                    onPressed: () => _backup(context), icon: const Icon(Icons.download), label: Text(tx('Export backup', 'تصدير نسخة احتياطية'))),
                OutlinedButton.icon(
                    onPressed: () => _restore(context),
                    icon: const Icon(Icons.upload_file),
                    label: Text(tx('Restore from backup', 'استرجاع من نسخة احتياطية'))),
                OutlinedButton.icon(
                    onPressed: () => exportExcel(store),
                    icon: const Icon(Icons.table_view),
                    label: Text(tx('Export to Excel', 'تصدير إلى Excel'))),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            title: Text(tx('Data', 'البيانات')),
            subtitle: Text(tx(
                '${store.items.length} items · ${store.receipts.length} receipts · '
                    '${store.purchases.length} purchases\nStarted from: ${store.source ?? '—'}',
                '${store.items.length} مادة · ${store.receipts.length} وصل · '
                    '${store.purchases.length} شراء\nالبداية من: ${store.source ?? '—'}')),
            isThreeLine: true,
            trailing: TextButton(onPressed: () => _erase(context), child: Text(tx('Erase all data', 'مسح كل البيانات'))),
          ),
        ),
      ]),
    );
  }
}

class _BusinessCard extends StatefulWidget {
  const _BusinessCard({required this.store});
  final WarehouseStore store;

  @override
  State<_BusinessCard> createState() => _BusinessCardState();
}

class _BusinessCardState extends State<_BusinessCard> {
  late final _name = TextEditingController(text: widget.store.companyName);

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(tx('Your business', 'عملك'), style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: ListenableBuilder(
                  listenable: _name,
                  builder: (_, _) => TextField(
                    controller: _name,
                    textDirection: dirOf(_name.text),
                    decoration: InputDecoration(labelText: tx('Business name (shown on invoices)', 'اسم العمل (يظهر على الفواتير)')),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed: () {
                  widget.store.setCompanyName(_name.text);
                  toast(context, tx('Saved.', 'تم الحفظ.'));
                },
                child: Text(tx('Save', 'حفظ')),
              ),
            ]),
          ]),
        ),
      );
}

/// Day/night mode, colour and text size for this device.
class AppearanceCard extends StatelessWidget {
  const AppearanceCard({super.key, required this.store});
  final WarehouseStore store;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tx('Appearance', 'المظهر'), style: t.textTheme.titleLarge),
          Text(tx('Saved on this device only.', 'يُحفظ على هذا الجهاز فقط.'), style: t.textTheme.bodySmall),
          const SizedBox(height: 14),
          Text(tx('Mode', 'الوضع'), style: t.textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'light', icon: const Icon(Icons.light_mode_outlined), label: Text(tx('Day', 'نهاري'))),
              ButtonSegment(value: 'dark', icon: const Icon(Icons.dark_mode_outlined), label: Text(tx('Night', 'ليلي'))),
              ButtonSegment(value: 'system', icon: const Icon(Icons.brightness_auto_outlined), label: Text(tx('Auto', 'تلقائي'))),
            ],
            selected: {store.themeMode},
            showSelectedIcon: false,
            onSelectionChanged: (v) => store.setLook(mode: v.first),
          ),
          const SizedBox(height: 16),
          Text(tx('Colour', 'اللون'), style: t.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for (final (i, (en, ar, c)) in accentChoices.indexed)
              Tooltip(
                message: tx(en, ar),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => store.setLook(accentIndex: i),
                  child: Semantics(
                    button: true,
                    label: tx(en, ar),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: store.accent == i ? t.colorScheme.onSurface : Colors.transparent, width: 3),
                      ),
                      child: store.accent == i ? const Icon(Icons.check, color: Colors.white) : null,
                    ),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 16),
          Text(tx('Text size', 'حجم الخط'), style: t.textTheme.titleSmall),
          const SizedBox(height: 6),
          SegmentedButton<double>(
            segments: [
              ButtonSegment(value: 1.0, label: Text(tx('Normal', 'عادي'))),
              ButtonSegment(value: 1.15, label: Text(tx('Large', 'كبير'))),
              ButtonSegment(value: 1.3, label: Text(tx('Larger', 'أكبر'))),
            ],
            selected: {store.textSize},
            showSelectedIcon: false,
            onSelectionChanged: (v) => store.setLook(size: v.first),
          ),
        ]),
      ),
    );
  }
}
