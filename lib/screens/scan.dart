import 'package:flutter/material.dart';

import '../l10n.dart';
import '../platform/scan.dart';
import '../store.dart';
import '../ui.dart';

/// Opens the camera and returns the first barcode or QR code read (or a code typed by hand).
Future<String?> scanCode(BuildContext context) => showDialog<String>(context: context, builder: (_) => const _ScanDialog());

/// Scans a code and returns the item it belongs to. Tells the user when no item has that code.
Future<String?> scanItem(BuildContext context, WarehouseStore store) async {
  final code = await scanCode(context);
  if (code == null || !context.mounted) return null;
  final item = store.itemByCode(code);
  if (item == null) toast(context, tx('No item has the code $code.', 'لا توجد مادة بالرمز $code.'));
  return item?.id;
}

class _ScanDialog extends StatefulWidget {
  const _ScanDialog();

  @override
  State<_ScanDialog> createState() => _ScanDialogState();
}

class _ScanDialogState extends State<_ScanDialog> {
  final _typed = TextEditingController();
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    stopScanner();
    super.dispose();
  }

  void _found(String code) {
    if (_done || !mounted || code.trim().isEmpty) return;
    _done = true;
    Navigator.pop(context, code.trim());
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Dialog(
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
            child: Row(children: [
              const Icon(Icons.qr_code_scanner),
              const SizedBox(width: 10),
              Expanded(child: Text(tx('Scan a barcode', 'قراءة الباركود'), style: t.textTheme.titleLarge)),
              IconButton(tooltip: tx('Close', 'إغلاق'), icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            ]),
          ),
          SizedBox(
            height: 300,
            child: !scannerAvailable || _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        tx('The camera could not be opened. Allow camera access for this app in Safari settings, or type the code below.',
                            'تعذّر فتح الكاميرا. اسمح للتطبيق باستخدام الكاميرا من إعدادات Safari، أو اكتب الرمز في الأسفل.'),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : Stack(fit: StackFit.expand, children: [
                    scannerView(onCode: _found, onError: (e) => mounted ? setState(() => _error = e) : null),
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          width: 260,
                          height: 150,
                          decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  ]),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _typed,
                  onSubmitted: _found,
                  decoration: InputDecoration(labelText: tx('Or type the code', 'أو اكتب الرمز'), border: const OutlineInputBorder(), isDense: true),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: () => _found(_typed.text), child: Text(tx('Find', 'بحث'))),
            ]),
          ),
        ]),
      ),
    );
  }
}
