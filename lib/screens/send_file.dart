import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../platform/files.dart';
import '../ui.dart';

/// A sheet for a PDF that is being made: once ready, send it straight to another app (WhatsApp,
/// Telegram, Mail, AirDrop ...), print it, or save it to Files. The file is made first so the
/// "Send" tap opens the share sheet at once, which Safari requires.
Future<void> showPdfSheet(BuildContext context, {required String name, required Future<Uint8List> Function() make, Future<void> Function()? print}) {
  final file = name.endsWith('.pdf') ? name : '$name.pdf';
  final bytes = make();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: FutureBuilder<Uint8List>(
        future: bytes,
        builder: (c, snap) {
          final ready = snap.hasData;
          final t = Theme.of(c);
          return Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: t.colorScheme.errorContainer,
                child: Icon(Icons.picture_as_pdf, color: t.colorScheme.onErrorContainer),
              ),
              title: Text(file, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(snap.hasError
                  ? tx('The file could not be made.', 'تعذّر إنشاء الملف.')
                  : ready
                      ? tx('Ready', 'جاهز')
                      : tx('Making the file…', 'جارٍ إنشاء الملف…')),
              trailing: ready || snap.hasError ? null : const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
            ),
            const Divider(height: 1),
            ListTile(
              enabled: ready,
              leading: const Icon(Icons.ios_share),
              title: Text(tx('Send', 'إرسال'), style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(tx('WhatsApp, Telegram, Mail and more', 'واتساب، تيليكرام، البريد وغيرها')),
              onTap: () async {
                // Nothing may be awaited before this call, or Safari refuses to open the share sheet.
                final r = shareFile(file, snap.data!, 'application/pdf');
                Navigator.pop(c);
                if (await r == ShareResult.unsupported && context.mounted) {
                  toast(context, tx('This browser cannot send files. Use "Save to Files" instead.', 'هذا المتصفح لا يدعم إرسال الملفات. استخدم "حفظ في الملفات".'));
                }
              },
            ),
            if (print != null)
              ListTile(
                leading: const Icon(Icons.print_outlined),
                title: Text(tx('Print', 'طباعة')),
                onTap: () {
                  Navigator.pop(c);
                  print();
                },
              ),
            ListTile(
              enabled: ready,
              leading: const Icon(Icons.download_outlined),
              title: Text(tx('Save to Files', 'حفظ في الملفات')),
              onTap: () {
                downloadFile(file, snap.data!, 'application/pdf');
                Navigator.pop(c);
              },
            ),
            const SizedBox(height: 8),
          ]);
        },
      ),
    ),
  );
}
