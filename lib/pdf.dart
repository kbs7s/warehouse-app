import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'l10n.dart';
import 'models.dart';
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

Future<Uint8List> buildReceiptPdf(WarehouseStore store, Receipt r) async {
  final doc = pw.Document(theme: await _pdfTheme(), title: tx('Receipt ${r.no}', 'وصل ${r.no}'));
  const cell = pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5);
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);

  pw.Widget info(String label, String value) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 4),
        child: pw.Row(children: [
          pw.SizedBox(width: 90, child: pw.Text(label, style: const pw.TextStyle(color: PdfColors.grey700))),
          _name(value, style: bold),
        ]),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    textDirection: _dir,
    margin: const pw.EdgeInsets.all(32),
    header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text(tx('Issue Receipt', 'وصل صرف'), style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        _name('قسم التجهيز', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      ]),
      pw.Divider(),
    ]),
    footer: (c) => pw.Align(
        alignment: _end,
        child: pw.Text(tx('Receipt #${r.no} · page ${c.pageNumber} of ${c.pagesCount}', 'وصل رقم ${r.no} · صفحة ${c.pageNumber} من ${c.pagesCount}'),
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))),
    build: (_) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          info(tx('Department', 'القسم'), r.department ?? '—'),
          info(tx('Received by', 'المستلم'), r.customer ?? '—'),
          if (r.note != null) info(tx('Note', 'ملاحظة'), r.note!),
        ])),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          info(tx('Receipt #', 'رقم الوصل'), '${r.no}'),
          info(tx('Date', 'التاريخ'), fmtDate(r.date)),
          info(tx('Items', 'المواد'), '${r.lines.length}'),
        ]),
      ]),
      pw.SizedBox(height: 16),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
        columnWidths: _widths(const [
          pw.FixedColumnWidth(28),
          pw.FixedColumnWidth(50),
          pw.FlexColumnWidth(),
          pw.FixedColumnWidth(60),
          pw.FixedColumnWidth(70),
        ]),
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: _cols([
              for (final h in ['#', tx('Code', 'الرمز'), tx('Item', 'المادة'), tx('Qty', 'الكمية'), tx('Unit', 'الوحدة')]) pw.Padding(padding: cell, child: pw.Text(h, style: bold)),
            ]),
          ),
          for (final (i, l) in r.lines.indexed)
            pw.TableRow(children: _cols([
              pw.Padding(padding: cell, child: pw.Text('${i + 1}')),
              pw.Padding(padding: cell, child: pw.Text(l.itemId)),
              pw.Padding(padding: cell, child: _name(store.item(l.itemId)?.name ?? l.itemId)),
              pw.Padding(padding: cell, child: pw.Text(fmtQty(l.qty), textAlign: _num)),
              pw.Padding(padding: cell, child: _name(store.item(l.itemId)?.unit ?? '')),
            ])),
        ],
      ),
      pw.SizedBox(height: 48),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        for (final s in [tx('Issued by (store keeper)', 'المُسلِّم (أمين المخزن)'), tx('Received by', 'المستلم')])
          pw.Column(children: [
            pw.Container(width: 180, height: .7, color: PdfColors.grey700),
            pw.SizedBox(height: 4),
            pw.Text(s),
          ]),
      ]),
    ],
  ));
  return doc.save();
}

/// Opens the iPad print / share sheet for a receipt (print, save to Files, send).
Future<void> shareReceiptPdf(WarehouseStore store, Receipt r) => Printing.layoutPdf(
      name: 'Receipt-${r.no}.pdf',
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
