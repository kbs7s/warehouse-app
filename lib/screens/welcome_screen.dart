import 'dart:convert';

import 'package:flutter/material.dart';

import '../platform/files.dart';
import '../store.dart';
import '../ui.dart';

/// First screen on a new iPad: load the data file (Excel import or a backup), or start empty.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.store});
  final WarehouseStore store;

  Future<void> _load(BuildContext context) async {
    final text = await pickTextFile();
    if (text == null) return;
    try {
      store.applyJson(jsonDecode(text) as Map<String, dynamic>);
    } catch (e) {
      if (context.mounted) toast(context, 'That file is not a data file or backup from this app.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Widget point(IconData i, String title, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: t.colorScheme.primaryContainer,
            child: Icon(i, size: 18, color: t.colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(text, style: TextStyle(color: t.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: t.colorScheme.primary, borderRadius: BorderRadius.circular(18)),
                      child: const Icon(Icons.inventory_2, color: Colors.white, size: 34),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Run your business\nwithout bookkeeping',
                    style: t.textTheme.headlineMedium!.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 24),
                  point(Icons.receipt_long, 'Bill clients', 'Invoices, part payments and who owes you what.'),
                  point(
                    Icons.layers_outlined,
                    'Know your stock value',
                    'Every purchase is a cost layer; the oldest is used first.',
                  ),
                  point(Icons.savings_outlined, 'See your real profit', 'In plain words, by month, with an assistant to ask.'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _load(context),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Load data file or backup'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(onPressed: store.startEmpty, child: const Text('Start fresh')),
                  const SizedBox(height: 16),
                  Text(
                    'Your data stays on this device. Export a backup from Settings each week.',
                    textAlign: TextAlign.center,
                    style: t.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
