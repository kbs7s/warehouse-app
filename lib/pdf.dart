import 'package:flutter/services.dart';
import 'package:barcode/barcode.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'l10n.dart';
import 'expiry.dart';
import 'models.dart';
import 'month.dart';
import 'store.dart';
import 'ui.dart';

bool _loaded = false;
late pw.Font _arabic, _arabicBold, _latin, _latinBold;

/// Latin-first theme for English documents, Arabic-first for Arabic ones.
Future<pw.ThemeData> _pdfTheme() async {
  if (!_loaded) {
    Future<pw.Font> f(String name) async => pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));
    _arabic = await f('NotoSansArabic-Regular');
    _arabicBold = await f('NotoSansArabic-Bold');
    _latin = await f('NotoSans-Regular');
    _latinBold = await f('NotoSans-Bold');
    _loaded = true;
  }
  return isAr
      ? pw.ThemeData.withFont(base: _arabic, bold: _arabicBold, fontFallback: [_latin])
      : pw.ThemeData.withFont(base: _latin, bold: _latinBold, fontFallback: [_arabic]);
}

pw.TextDirection get _dir => isAr ? pw.TextDirection.rtl : pw.TextDirection.ltr;
pw.Alignment get _end => isAr ? pw.Alignment.centerLeft : pw.Alignment.centerRight;
pw.TextAlign get _num => isAr ? pw.TextAlign.left : pw.TextAlign.right;

// pw.Table ignores text direction, so Arabic documents lay table columns out in reverse.
List<T> _cols<T>(List<T> l) => isAr ? l.reversed.toList() : l;
Map<int, pw.TableColumnWidth> _widths(List<pw.TableColumnWidth> w) => {for (final (i, x) in _cols(w).indexed) i: x};

/// User-entered names: Arabic text must be set in the Arabic font itself so the letters join.
pw.Widget _name(String s, {pw.TextStyle? style, pw.TextAlign? align}) {
  if (dirOf(s).name != 'rtl') return pw.Text(s, style: style, textAlign: align);
  final bold = style?.fontWeight == pw.FontWeight.bold;
  return pw.Text(s,
      style: (style ?? const pw.TextStyle()).copyWith(font: bold ? _arabicBold : _arabic, fontFallback: [_latin]),
      textAlign: align,
      textDirection: pw.TextDirection.rtl);
}

// Issue receipt colours: deep teal ink, teal accent, quiet greys.
const _ink = PdfColor.fromInt(0xFF0F3D3E);
const _teal = PdfColor.fromInt(0xFF0D9488);
const _tealSoft = PdfColor.fromInt(0xFFF0FDFA);
const _muted = PdfColor.fromInt(0xFF64748B);
const _line = PdfColor.fromInt(0xFFE2E8F0);
const _tint = PdfColor.fromInt(0xFFF6F8FA);
const _text = PdfColor.fromInt(0xFF1E293B);

/// The issue receipt, laid out as an A4 form ready to print or send to the department on WhatsApp.
/// Three type sizes: 7.5 for labels, 9 for the body and table, 13 for the title and number.
Future<Uint8List> buildReceiptPdf(WarehouseStore store, Receipt r) async {
  final doc = pw.Document(
      theme: await _pdfTheme(),
      title: tx('Issue receipt ${r.no}', 'وصل صرف ${r.no}'));
  final company = store.companyName.isEmpty ? 'قسم التجهيز' : store.companyName;
  final dept = r.department ?? '—';
  final date = fmtDate(r.date);
  final note = [if (r.fromReserve) tx('From the reserve store', 'من مخزن الاحتياط'), if (r.note != null && r.note!.trim().isNotEmpty) r.note!.trim()].join(' · ');

  const label = 7.5, body = 9.0, title = 13.0;
  pw.TextStyle st(double size, {bool bold = false, PdfColor color = _text}) =>
      pw.TextStyle(fontSize: size, color: color, lineSpacing: 0, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
  pw.Widget tx_(String v, pw.TextStyle style) => _name(v, style: style);
  final start = isAr ? pw.Alignment.centerRight : pw.Alignment.centerLeft;

  // A compact band: store, title, number on one line over a single rule.
  pw.Widget header(pw.Context c) {
    final first = c.pageNumber == 1;
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          pw.Expanded(
            child: pw.Row(children: [
              pw.Container(
                width: 20,
                height: 20,
                alignment: pw.Alignment.center,
                decoration: pw.BoxDecoration(color: _ink, borderRadius: pw.BorderRadius.circular(4)),
                child: pw.Text('+', style: st(body + 2, bold: true, color: PdfColors.white)),
              ),
              pw.SizedBox(width: 7),
              pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                tx_(company, st(body + 1, bold: true, color: _ink)),
                pw.Text(tx('Stores and medical supplies', 'إدارة المخازن والمستلزمات الطبية'), style: st(label, color: _muted)),
              ]),
            ]),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            decoration: pw.BoxDecoration(color: _tealSoft, border: pw.Border.all(color: _teal, width: .8), borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Column(children: [
              pw.Text(tx('Issue receipt', 'وصل صرف'), style: st(title, bold: true, color: _ink)),
              if (!first) pw.Text(tx('Continued', 'تابع'), style: st(label, color: _teal)),
            ]),
          ),
          pw.Expanded(
            child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
              pw.Text('${tx('Receipt no.', 'رقم الوصل')}  ', style: st(label, color: _muted)),
              pw.Text('#${r.no}', style: st(title, bold: true, color: _ink), textDirection: pw.TextDirection.ltr),
            ]),
          ),
        ]),
        pw.SizedBox(height: 6),
        pw.Container(height: 1.4, color: _ink),
        if (!first) ...[
          pw.SizedBox(height: 6),
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Row(children: [
              pw.Text('${tx('Department', 'القسم')}: ', style: st(body, color: _muted)),
              tx_(dept, st(body, bold: true)),
            ]),
            pw.Row(children: [
              pw.Text('${tx('Date', 'التاريخ')}: ', style: st(body, color: _muted)),
              pw.Text(date, style: st(body, bold: true)),
            ]),
          ]),
        ],
      ]),
    );
  }

  // One label over one value; every field starts on the same edge.
  pw.Widget field(String l, pw.Widget v) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(l, style: st(label, color: _muted)),
        pw.SizedBox(height: 2),
        v,
      ]);
  pw.Widget fieldText(String l, String v) => field(l, tx_(v, st(body, bold: true)));
  final receiver = r.customer?.trim() ?? '';
  final blank = pw.Container(height: 12, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: _muted, width: .5, style: pw.BorderStyle.dashed))));

  const cell = pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2.0);
  pw.Widget td(pw.Widget w, {pw.Alignment align = pw.Alignment.center}) => pw.Container(padding: cell, alignment: align, child: w);

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    textDirection: _dir,
    margin: const pw.EdgeInsets.fromLTRB(36, 26, 36, 18),
    header: header,
    footer: (c) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 6),
      child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        tx_(company, st(label, color: _muted)),
        pw.Text(tx('Receipt ${r.no} · page ${c.pageNumber} of ${c.pagesCount}', 'وصل ${r.no} · صفحة ${c.pageNumber} من ${c.pagesCount}'), style: st(label, color: _muted)),
      ]),
    ),
    build: (_) => [
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: pw.BoxDecoration(color: _tint, borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(flex: 3, child: fieldText(tx('Department', 'القسم المستفيد'), dept)),
          pw.Expanded(flex: 3, child: fieldText(tx('Issue date', 'تاريخ الصرف'), date)),
          pw.Expanded(flex: 2, child: fieldText(tx('Items', 'عدد المواد'), tx('${r.lines.length} items', '${r.lines.length} مادة'))),
          pw.Expanded(flex: 2, child: fieldText(tx('Note', 'ملاحظة'), note.isEmpty ? '—' : note)),
          pw.Expanded(
              flex: 4,
              child: receiver.isEmpty
                  ? field(tx('Received by (name)', 'اسم المستلم'), pw.Padding(padding: const pw.EdgeInsets.only(top: 2), child: blank))
                  : fieldText(tx('Received by (name)', 'اسم المستلم'), receiver)),
        ]),
      ),
      pw.SizedBox(height: 8),
      pw.Table(
        border: const pw.TableBorder(horizontalInside: pw.BorderSide(color: _line, width: .6), bottom: pw.BorderSide(color: _line, width: .6)),
        columnWidths: _widths(const [
          pw.FixedColumnWidth(26),
          pw.FixedColumnWidth(52),
          pw.FlexColumnWidth(),
          pw.FixedColumnWidth(56),
          pw.FixedColumnWidth(70),
        ]),
        children: [
          pw.TableRow(
            repeat: true,
            decoration: const pw.BoxDecoration(color: _ink),
            children: _cols([
              for (final (i, h) in ['#', tx('Code', 'الرمز'), tx('Item', 'المادة'), tx('Qty', 'الكمية'), tx('Unit', 'الوحدة')].indexed)
                td(pw.Text(h, style: st(label + .5, bold: true, color: PdfColors.white)), align: i == 2 ? start : pw.Alignment.center),
            ]),
          ),
          for (final (i, l) in r.lines.indexed)
            pw.TableRow(
              decoration: i.isOdd ? const pw.BoxDecoration(color: _tint) : null,
              children: _cols([
                td(pw.Text('${i + 1}', style: st(label, color: _muted))),
                td(pw.Text(l.itemId, style: st(label + .5, color: _muted), textDirection: pw.TextDirection.ltr)),
                td(tx_(store.item(l.itemId)?.name ?? l.itemId, st(body, bold: true)), align: start),
                td(pw.Text(fmtQty(l.qty), style: st(body, bold: true, color: _ink), textDirection: pw.TextDirection.ltr)),
                td(tx_(store.item(l.itemId)?.unit ?? '', st(label + .5, color: _muted))),
              ]),
            ),
        ],
      ),
      pw.SizedBox(height: 12),
      pw.Row(children: [
        for (final (i, t) in [tx('Issued by (store keeper)', 'المُسلِّم (أمين المخزن)'), tx('Received by', 'المستلم')].indexed) ...[
          if (i > 0) pw.SizedBox(width: 40),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(t, style: st(body, bold: true, color: _ink)),
              pw.SizedBox(height: 18),
              pw.Container(height: .6, color: _muted),
              pw.SizedBox(height: 3),
              pw.Text(tx('Name and signature', 'الاسم والتوقيع'), style: st(label, color: _muted)),
            ]),
          ),
        ],
      ]),
    ],
  ));
  return doc.save();
}

/// "وصل صرف 49 - عمليات.pdf": the file name the department sees on WhatsApp.
String receiptFileName(Receipt r) {
  final dept = (r.department ?? '').replaceAll(RegExp(r'[\\/:*?"<>|]'), '-').trim();
  return '${tx('Issue receipt', 'وصل صرف')} ${r.no}${dept.isEmpty ? '' : ' - $dept'}.pdf';
}

/// Opens the iPad print / share sheet for a receipt (print, save to Files, send).
Future<void> shareReceiptPdf(WarehouseStore store, Receipt r) => Printing.layoutPdf(
      name: receiptFileName(r),
      onLayout: (_) => buildReceiptPdf(store, r),
    );

Future<Uint8List> buildInvoicePdf(WarehouseStore store, Invoice inv) async {
  final doc = pw.Document(theme: await _pdfTheme(), title: tx('Invoice ${inv.no}', 'فاتورة ${inv.no}'));
  const cell = pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5);
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  final client = store.client(inv.clientId);
  const grey = pw.TextStyle(color: PdfColors.grey700);

  pw.Widget total(String label, String value, {bool strong = false}) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 3),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
          pw.SizedBox(width: 120, child: pw.Text(label, style: strong ? bold : grey)),
          pw.SizedBox(width: 120, child: pw.Text(value, style: strong ? bold : null, textAlign: _num)),
        ]),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    textDirection: _dir,
    margin: const pw.EdgeInsets.all(36),
    header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(tx('INVOICE', 'فاتورة'), style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0F766E))),
        _name(store.companyName.isEmpty ? ' ' : store.companyName, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
      ]),
      pw.Divider(color: PdfColors.grey400),
    ]),
    footer: (c) => pw.Align(
        alignment: _end,
        child: pw.Text(tx('Invoice #${inv.no} · page ${c.pageNumber} of ${c.pagesCount}', 'فاتورة رقم ${inv.no} · صفحة ${c.pageNumber} من ${c.pagesCount}'),
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))),
    build: (_) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(tx('Bill to', 'إلى'), style: grey),
            _name(client?.name ?? '—', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            for (final x in [?client?.phone, ?client?.email, ?client?.address]) _name(x),
          ]),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text(tx('Invoice #${inv.no}', 'فاتورة رقم ${inv.no}'), style: bold),
          pw.Text(tx('Date: ${fmtDate(inv.date)}', 'التاريخ: ${fmtDate(inv.date)}')),
          if (inv.dueDate != null) pw.Text(tx('Pay by: ${fmtDate(inv.dueDate)}', 'تُدفع قبل: ${fmtDate(inv.dueDate)}')),
        ]),
      ]),
      pw.SizedBox(height: 18),
      pw.Table(
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: .5)),
        columnWidths: _widths(const [
          pw.FixedColumnWidth(24),
          pw.FlexColumnWidth(),
          pw.FixedColumnWidth(55),
          pw.FixedColumnWidth(90),
          pw.FixedColumnWidth(100),
        ]),
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: _cols([
              for (final (i, h) in ['#', tx('Description', 'الوصف'), tx('Qty', 'الكمية'), tx('Price', 'السعر'), tx('Amount', 'المبلغ')].indexed)
                pw.Padding(padding: cell, child: pw.Text(h, style: bold, textAlign: i >= 2 ? _num : null)),
            ]),
          ),
          for (final (i, l) in inv.lines.indexed)
            pw.TableRow(children: _cols([
              pw.Padding(padding: cell, child: pw.Text('${i + 1}')),
              pw.Padding(
                  padding: cell,
                  child: _name(l.itemId == null ? (l.description ?? '') : (store.item(l.itemId!)?.name ?? l.itemId!))),
              pw.Padding(padding: cell, child: pw.Text(fmtQty(l.qty), textAlign: _num)),
              pw.Padding(padding: cell, child: pw.Text(fmtQty(l.unitPrice), textAlign: _num)),
              pw.Padding(padding: cell, child: pw.Text(fmtQty(l.total), textAlign: _num)),
            ])),
        ],
      ),
      pw.SizedBox(height: 12),
      total(tx('Subtotal', 'المجموع الفرعي'), fmtMoney(inv.subtotal)),
      if (inv.discount != 0) total(tx('Discount', 'الخصم'), '-${fmtMoney(inv.discount)}'),
      total(tx('Total', 'المجموع'), fmtMoney(inv.total), strong: true),
      if (inv.paid > 0) total(tx('Paid', 'المدفوع'), fmtMoney(inv.paid)),
      if (inv.paid > 0) total(tx('Balance due', 'المتبقي للدفع'), fmtMoney(inv.balance), strong: true),
      if (inv.note != null) ...[pw.SizedBox(height: 18), _name(inv.note!)],
      pw.SizedBox(height: 30),
      pw.Text(tx('Thank you for your business.', 'شكراً لتعاملكم معنا.'), style: grey),
    ],
  ));
  return doc.save();
}

Future<void> shareInvoicePdf(WarehouseStore store, Invoice inv) => Printing.layoutPdf(
      name: 'Invoice-${inv.no}.pdf',
      onLayout: (_) => buildInvoicePdf(store, inv),
    );

/// Monthly report: what each department took between [from] and [to] (both included).
Future<Uint8List> buildDepartmentsPdf(WarehouseStore store, String from, String to, String title) async {
  final doc = pw.Document(theme: await _pdfTheme(), title: title);
  const cell = pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4);
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);

  // Department -> item -> quantity, and receipts per department.
  final qty = <String, Map<String, num>>{};
  final count = <String, int>{};
  for (final r in store.allReceipts) {
    final d = r.date;
    if (d == null || d.compareTo(from) < 0 || d.compareTo(to) > 0) continue;
    final name = (r.department?.trim().isEmpty ?? true) ? tx('No department', 'بدون قسم') : r.department!.trim();
    count[name] = (count[name] ?? 0) + 1;
    final m = qty.putIfAbsent(name, () => {});
    for (final l in r.lines) {
      m[l.itemId] = (m[l.itemId] ?? 0) + l.qty;
    }
  }
  num total(Map<String, num> m) => m.values.fold<num>(0, (a, b) => a + b);
  final depts = qty.keys.toList()..sort((a, b) => total(qty[b]!).compareTo(total(qty[a]!)));

  pw.Widget table(List<pw.TableColumnWidth> widths, List<String> header, List<List<pw.Widget>> rows) => pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
        columnWidths: _widths(widths),
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: _cols([for (final h in header) pw.Padding(padding: cell, child: pw.Text(h, style: bold))]),
          ),
          for (final r in rows) pw.TableRow(children: _cols([for (final c in r) pw.Padding(padding: cell, child: c)])),
        ],
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    textDirection: _dir,
    margin: const pw.EdgeInsets.all(32),
    header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(title, style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
        _name(store.companyName.isEmpty ? 'قسم التجهيز' : store.companyName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      ]),
      pw.Text(from.startsWith('0000') ? tx('All records', 'كل السجلات') : '${fmtDate(from)} – ${fmtDate(to)}', style: const pw.TextStyle(color: PdfColors.grey700)),
      pw.Divider(),
    ]),
    footer: (c) => pw.Align(
        alignment: _end,
        child: pw.Text(tx('Page ${c.pageNumber} of ${c.pagesCount}', 'صفحة ${c.pageNumber} من ${c.pagesCount}'),
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))),
    build: (_) => [
      if (depts.isEmpty)
        pw.Padding(padding: const pw.EdgeInsets.all(24), child: pw.Text(tx('Nothing was issued in these dates.', 'لا يوجد صرف في هذه التواريخ.')))
      else ...[
        pw.Text(tx('Summary', 'الملخص'), style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        table(
          const [pw.FlexColumnWidth(), pw.FixedColumnWidth(70), pw.FixedColumnWidth(70), pw.FixedColumnWidth(80)],
          [tx('Department', 'القسم'), tx('Receipts', 'الوصولات'), tx('Items', 'المواد'), tx('Quantity', 'الكمية')],
          [
            for (final d in depts)
              [
                _name(d),
                pw.Text('${count[d]}', textAlign: _num),
                pw.Text('${qty[d]!.length}', textAlign: _num),
                pw.Text(fmtQty(total(qty[d]!)), textAlign: _num),
              ],
          ],
        ),
        for (final d in depts) ...[
          pw.SizedBox(height: 18),
          pw.Row(children: [
            _name(d, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
            pw.Text('  ·  ${tx('${count[d]} receipts', '${count[d]} وصل')}', style: const pw.TextStyle(color: PdfColors.grey700)),
          ]),
          pw.SizedBox(height: 6),
          table(
            const [pw.FixedColumnWidth(50), pw.FlexColumnWidth(), pw.FixedColumnWidth(70), pw.FixedColumnWidth(70)],
            [tx('Code', 'الرمز'), tx('Item', 'المادة'), tx('Qty', 'الكمية'), tx('Unit', 'الوحدة')],
            [
              for (final e in (qty[d]!.entries.toList()..sort((a, b) => b.value.compareTo(a.value))))
                [
                  pw.Text(e.key),
                  _name(store.item(e.key)?.name ?? e.key),
                  pw.Text(fmtQty(e.value), textAlign: _num),
                  _name(store.item(e.key)?.unit ?? ''),
                ],
            ],
          ),
        ],
      ],
    ],
  ));
  return doc.save();
}

/// Opens the print / share sheet for the department report.
Future<void> shareDepartmentsPdf(WarehouseStore store, String from, String to, String title) => Printing.layoutPdf(
      name: '${title.replaceAll('/', '-')}.pdf',
      onLayout: (_) => buildDepartmentsPdf(store, from, to, title),
    );


/// Sticker sheet: one label per item with its name, unit and a barcode (or QR code) of its code,
/// [copies] of each, on A4 in a grid of 3 across.
Future<Uint8List> buildLabelsPdf(WarehouseStore store, List<Item> items, {bool qr = false, int copies = 1}) async {
  final doc = pw.Document(theme: await _pdfTheme(), title: tx('Item labels', 'ملصقات المواد'));
  final labels = [for (final i in items) for (var k = 0; k < copies; k++) i];
  pw.Widget label(Item i) => pw.Container(
        height: 120,
        padding: const pw.EdgeInsets.all(6),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey500, width: .5), borderRadius: pw.BorderRadius.circular(4)),
        child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          _name(i.name, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold), align: pw.TextAlign.center),
          pw.SizedBox(height: 4),
          pw.Expanded(
            child: pw.BarcodeWidget(
              barcode: qr ? Barcode.qrCode() : Barcode.code128(),
              data: (i.barcode ?? '').isNotEmpty ? i.barcode! : i.id,
              drawText: false,
            ),
          ),
          pw.SizedBox(height: 2),
          _name('${(i.barcode ?? '').isNotEmpty ? i.barcode! : i.id} · ${i.unit}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700), align: pw.TextAlign.center),
        ]),
      );
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    textDirection: _dir,
    margin: const pw.EdgeInsets.all(24),
    build: (_) => [
      pw.GridView(crossAxisCount: 3, childAspectRatio: 120 / 172, crossAxisSpacing: 8, mainAxisSpacing: 8, children: [for (final i in labels) label(i)]),
    ],
  ));
  return doc.save();
}

Future<void> shareLabelsPdf(WarehouseStore store, List<Item> items, {bool qr = false, int copies = 1}) => Printing.layoutPdf(
      name: 'Labels.pdf',
      onLayout: (_) => buildLabelsPdf(store, items, qr: qr, copies: copies),
    );


/// One-page-or-so month report for management: hospital figures, totals, spending per department,
/// most used items, items that ran out, and items expiring soon.
Future<Uint8List> buildMonthReportPdf(WarehouseStore store,
    {required String title, required String from, required String to, required List<MonthRow> rows,
    required Map<String, num> stats, required List<Receipt> issues, required List<Purchase> purchases}) async {
  final doc = pw.Document(theme: await _pdfTheme(), title: title);
  const cell = pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4);
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  const teal = PdfColor.fromInt(0xFF0F766E);
  num cost(String id, num q) => store.ledger.estimateCost(id, q);

  // Spending per department: issues, items, and value at cost.
  final dept = <String, ({int n, num qty, num value})>{};
  for (final r in issues) {
    final d = (r.department ?? '').trim().isEmpty ? tx('No department', 'بدون قسم') : r.department!.trim();
    final old = dept[d] ?? (n: 0, qty: 0, value: 0);
    dept[d] = (
      n: old.n + 1,
      qty: old.qty + r.lines.fold<num>(0, (s, l) => s + l.qty),
      value: old.value + r.lines.fold<num>(0, (s, l) => s + cost(l.itemId, l.qty)),
    );
  }
  final depts = dept.entries.toList()..sort((a, b) => b.value.value.compareTo(a.value.value));
  final issuedValue = depts.fold<num>(0, (s, e) => s + e.value.value);
  final bought = purchases.fold<num>(0, (s, p) => s + p.total);
  final top = (rows.where((r) => r.issued > 0).toList()..sort((a, b) => b.issued.compareTo(a.issued))).take(10).toList();
  final ranOut = [for (final r in rows) if (r.closing <= 0 && (r.issued > 0 || r.opening > 0)) r];
  final expiring = [for (final e in store.expiryAlerts) e].take(15).toList();

  pw.Widget heading(String t) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 6), child: pw.Text(t, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: teal)));
  pw.Widget table(List<String> head, List<List<String>> body, List<pw.TableColumnWidth> widths, {Set<int> numeric = const {}}) => pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
        columnWidths: _widths(widths),
        children: [
          pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: _cols([for (final h in head) pw.Padding(padding: cell, child: pw.Text(h, style: bold))])),
          for (final row in body)
            pw.TableRow(children: _cols([
              for (final (i, v) in row.indexed)
                pw.Padding(padding: cell, child: numeric.contains(i) ? pw.Text(v, textAlign: _num) : _name(v)),
            ])),
        ],
      );
  pw.Widget tile(String label, String value) => pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.symmetric(horizontal: 3),
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          ]),
        ),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    textDirection: _dir,
    margin: const pw.EdgeInsets.all(32),
    header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(tx('Month report · $title', 'تقرير الشهر · $title'), style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: teal)),
        _name(store.companyName.isEmpty ? 'قسم التجهيز' : store.companyName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      ]),
      pw.Text('${fmtDate(from)} – ${fmtDate(to)}', style: const pw.TextStyle(color: PdfColors.grey700)),
      pw.Divider(color: PdfColors.grey400),
    ]),
    footer: (c) => pw.Align(
        alignment: _end,
        child: pw.Text(tx('$title · page ${c.pageNumber} of ${c.pagesCount}', '$title · صفحة ${c.pageNumber} من ${c.pagesCount}'),
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))),
    build: (_) => [
      pw.Row(children: [
        tile(tx('Issue receipts', 'وصولات الصرف'), '${issues.length}'),
        tile(tx('Supplies used (cost)', 'قيمة المصروف'), fmtMoney(issuedValue)),
        tile(tx('Purchases', 'المشتريات'), '${purchases.length} · ${fmtMoney(bought)}'),
        tile(tx('Items that ran out', 'مواد نفدت'), '${ranOut.length}'),
      ]),
      if (stats.isNotEmpty) ...[
        heading(tx('Hospital figures', 'أرقام المستشفى')),
        pw.Row(children: [
          for (final k in monthStatKeys) tile(tx(k.$2, k.$3), stats[k.$1] == null ? '—' : fmtQty(stats[k.$1]!)),
        ]),
      ],
      heading(tx('Spending per department', 'الصرف حسب القسم')),
      if (depts.isEmpty)
        pw.Text(tx('No issues this month.', 'لا يوجد صرف هذا الشهر.'))
      else
        table(
          [tx('Department', 'القسم'), tx('Receipts', 'الوصولات'), tx('Quantity', 'الكمية'), tx('Value', 'القيمة'), '%'],
          [
            for (final e in depts)
              [
                e.key,
                '${e.value.n}',
                fmtQty(e.value.qty),
                fmtMoney(e.value.value),
                issuedValue == 0 ? '—' : '${(e.value.value * 100 / issuedValue).round()}%',
              ],
          ],
          const [pw.FlexColumnWidth(), pw.FixedColumnWidth(70), pw.FixedColumnWidth(70), pw.FixedColumnWidth(100), pw.FixedColumnWidth(40)],
          numeric: {1, 2, 3, 4},
        ),
      heading(tx('Most used items', 'المواد الأكثر استخداماً')),
      if (top.isEmpty)
        pw.Text('—')
      else
        table(
          [tx('Item', 'المادة'), tx('Used', 'المصروف'), tx('Unit', 'الوحدة'), tx('Left at month end', 'الباقي نهاية الشهر')],
          [for (final r in top) [r.name, fmtQty(r.issued), r.unit, fmtQty(r.closing)]],
          const [pw.FlexColumnWidth(), pw.FixedColumnWidth(70), pw.FixedColumnWidth(70), pw.FixedColumnWidth(100)],
          numeric: {1, 3},
        ),
      heading(tx('Items that ran out', 'المواد التي نفدت')),
      if (ranOut.isEmpty)
        pw.Text(tx('None.', 'لا يوجد.'))
      else
        table(
          [tx('Item', 'المادة'), tx('Used this month', 'المصروف هذا الشهر'), tx('Left', 'الباقي')],
          [for (final r in ranOut) [r.name, fmtQty(r.issued), fmtQty(r.closing)]],
          const [pw.FlexColumnWidth(), pw.FixedColumnWidth(110), pw.FixedColumnWidth(70)],
          numeric: {1, 2},
        ),
      heading(tx('Expired or expiring soon (today)', 'منتهية أو قريبة الانتهاء (اليوم)')),
      if (expiring.isEmpty)
        pw.Text(tx('None.', 'لا يوجد.'))
      else
        table(
          [tx('Item', 'المادة'), tx('Expiry date', 'تاريخ الانتهاء'), tx('Quantity', 'الكمية'), tx('Status', 'الحالة')],
          [for (final e in expiring) [e.item.name, fmtDate(e.batch.date), e.batch.qty == null ? '—' : fmtQty(e.batch.qty!), e.label]],
          const [pw.FlexColumnWidth(), pw.FixedColumnWidth(90), pw.FixedColumnWidth(70), pw.FixedColumnWidth(110)],
          numeric: {2},
        ),
    ],
  ));
  return doc.save();
}
