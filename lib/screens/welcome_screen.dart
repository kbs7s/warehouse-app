import 'dart:convert';

import 'package:flutter/material.dart';

import '../l10n.dart';
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
      if (context.mounted) toast(context, tx('That file is not a data file or backup from this app.', 'هذا الملف ليس ملف بيانات أو نسخة احتياطية من هذا التطبيق.'));
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
                  Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: t.colorScheme.primary, borderRadius: BorderRadius.circular(18)),
                        child: const Icon(Icons.inventory_2, color: Colors.white, size: 34),
                      ),
                      const Spacer(),
                      LanguageChips(store: store),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    tx('Run your business\nwithout bookkeeping', 'أدِر عملك\nبدون محاسبة معقدة'),
                    style: t.textTheme.headlineMedium!.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 24),
                  point(Icons.receipt_long, tx('Bill clients', 'فوترة الزبائن'),
                      tx('Invoices, part payments and who owes you what.', 'الفواتير والدفعات الجزئية ومن عليه دين لك.')),
                  point(
                    Icons.layers_outlined,
                    tx('Know your stock value', 'اعرف قيمة مخزونك'),
                    tx('Every purchase is a cost layer; the oldest is used first.', 'كل شراء طبقة بكلفتها، والأقدم يُصرف أولاً.'),
                  ),
                  point(Icons.savings_outlined, tx('See your real profit', 'شاهد ربحك الحقيقي'),
                      tx('In plain words, by month, with an assistant to ask.', 'بكلمات بسيطة، شهراً بشهر، مع مساعد تسأله.')),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _load(context),
                    icon: const Icon(Icons.upload_file),
                    label: Text(tx('Load data file or backup', 'تحميل ملف بيانات أو نسخة احتياطية')),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(onPressed: store.startEmpty, child: Text(tx('Start fresh', 'ابدأ من جديد'))),
                  const SizedBox(height: 16),
                  Text(
                    tx('Your data stays on this device. Export a backup from Settings each week.',
                        'بياناتك تبقى على هذا الجهاز. صدّر نسخة احتياطية من الإعدادات كل أسبوع.'),
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

/// English / العربية switch, shown on the welcome screen and in Settings.
class LanguageChips extends StatelessWidget {
  const LanguageChips({super.key, required this.store});
  final WarehouseStore store;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        children: [
          for (final (code, label) in [('en', 'English'), ('ar', 'العربية')])
            ChoiceChip(
              label: Text(label),
              selected: store.lang == code,
              showCheckmark: false,
              onSelected: (_) => store.setLang(code),
            ),
        ],
      );
}
