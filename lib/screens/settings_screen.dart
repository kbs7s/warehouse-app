import 'dart:convert';

import 'package:flutter/material.dart';

import '../export.dart';
import '../platform/files.dart';
import '../store.dart';
import '../ui.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.store});
  final WarehouseStore store;

  Future<void> _backup(BuildContext context) async {
    final name = 'warehouse-backup-${todayIso()}.json';
    store.markBackedUp();
    await downloadFile(name, utf8.encode(jsonEncode(store.toJson())), 'application/json');
    if (context.mounted) toast(context, 'Backup saved as $name. Keep it in Files or iCloud Drive.');
  }

  Future<void> _restore(BuildContext context) async {
    final text = await pickTextFile();
    if (text == null || !context.mounted) return;
    try {
      final j = jsonDecode(text) as Map<String, dynamic>;
      if (!await confirm(context, 'Restore this backup?',
          'Everything in the app now will be replaced by the backup from ${j['savedAt'] ?? 'an unknown date'}.',
          action: 'Restore')) {
        return;
      }
      store.applyJson(j);
      if (context.mounted) toast(context, 'Backup restored.');
    } catch (e) {
      if (context.mounted) toast(context, 'Could not read that file: $e');
    }
  }

  Future<void> _erase(BuildContext context) async {
    if (!await confirm(context, 'Erase all data on this iPad?',
        'Every item, receipt, purchase and payment is deleted. Export a backup first if unsure.',
        action: 'Erase')) {
      return;
    }
    await store.eraseAll();
  }

  @override
  Widget build(BuildContext context) {
    final last = store.lastBackupAt == null ? null : DateTime.tryParse(store.lastBackupAt!);
    final days = last == null ? null : DateTime.now().difference(last).inDays;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & settings')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Backup', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('Your data is saved only on this iPad. Export a backup at least once a week and keep it in '
                  'Files or iCloud Drive, so nothing is lost if Safari data is cleared.'),
              const SizedBox(height: 8),
              Text(last == null ? 'No backup exported yet.' : 'Last backup: ${fmtDate(store.lastBackupAt)} ($days days ago)',
                  style: TextStyle(
                      fontWeight: FontWeight.w600, color: days == null || days > 7 ? Colors.red : Colors.green)),
              const SizedBox(height: 16),
              Wrap(spacing: 12, runSpacing: 12, children: [
                FilledButton.icon(
                    onPressed: () => _backup(context), icon: const Icon(Icons.download), label: const Text('Export backup')),
                OutlinedButton.icon(
                    onPressed: () => _restore(context),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Restore from backup')),
                OutlinedButton.icon(
                    onPressed: () => exportExcel(store),
                    icon: const Icon(Icons.table_view),
                    label: const Text('Export to Excel')),
              ]),
            ]),
          ),
        ),
        Card(
          child: ListTile(
            title: const Text('Data'),
            subtitle: Text('${store.items.length} items · ${store.receipts.length} receipts · '
                '${store.purchases.length} purchases\nStarted from: ${store.source ?? '—'}'),
            isThreeLine: true,
            trailing: TextButton(onPressed: () => _erase(context), child: const Text('Erase all data')),
          ),
        ),
      ]),
    );
  }
}
