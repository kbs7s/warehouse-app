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
      if (context.mounted) toast(context, 'That file is not a warehouse data file.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.inventory_2_outlined, size: 72),
                const SizedBox(height: 16),
                const Text('قسم التجهيز', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Warehouse issues & stock', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 32),
                const Text(
                  'Load your data file to begin: the Excel import (app_seed.json) or a backup you exported. '
                  'Your data is then kept on this iPad.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _load(context),
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Load data file'),
                ),
                const SizedBox(height: 12),
                TextButton(onPressed: store.startEmpty, child: const Text('Start with an empty warehouse')),
              ]),
            ),
          ),
        ),
      );
}
