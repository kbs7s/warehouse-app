import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'models.dart';
import 'store.dart';
import 'ui.dart';

pw.ThemeData? _theme;
late pw.Font _arabic, _arabicBold, _latin;

Future<pw.ThemeData> _pdfTheme() async {
  if (_theme != null) return _theme!;
  Future<pw.Font> f(String name) async => pw.Font.ttf(await rootBundle.load('assets/fonts/$name.ttf'));
  _arabic = await f('NotoSansArabic-Regular');
  _arabicBold = await f('NotoSansArabic-Bold');
  _latin = await f('NotoSans-Regular');
  return _theme = pw.ThemeData.withFont(base: _latin, bold: await f('NotoSans-Bold'), fontFallback: [_arabic]);
}

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
  final doc = pw.Document(theme: await _pdfTheme(), title: 'Receipt ${r.no}');
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
    margin: const pw.EdgeInsets.all(32),
    header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        pw.Text('Issue Receipt', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
        _name('قسم التجهيز', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
      ]),
      pw.Divider(),
    ]),
    footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Receipt #${r.no} · page ${c.pageNumber} of ${c.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))),
    build: (_) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          info('Department', r.department ?? '—'),
          info('Received by', r.customer ?? '—'),
          if (r.note != null) info('Note', r.note!),
        ])),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          info('Receipt #', '${r.no}'),
          info('Date', fmtDate(r.date)),
          info('Items', '${r.lines.length}'),
        ]),
      ]),
      pw.SizedBox(height: 16),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
        columnWidths: const {
          0: pw.FixedColumnWidth(28),
          1: pw.FixedColumnWidth(50),
          2: pw.FlexColumnWidth(),
          3: pw.FixedColumnWidth(60),
          4: pw.FixedColumnWidth(70),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              for (final h in ['#', 'Code', 'Item', 'Qty', 'Unit']) pw.Padding(padding: cell, child: pw.Text(h, style: bold)),
            ],
          ),
          for (final (i, l) in r.lines.indexed)
            pw.TableRow(children: [
              pw.Padding(padding: cell, child: pw.Text('${i + 1}')),
              pw.Padding(padding: cell, child: pw.Text(l.itemId)),
              pw.Padding(padding: cell, child: _name(store.item(l.itemId)?.name ?? l.itemId)),
              pw.Padding(padding: cell, child: pw.Text(fmtQty(l.qty), textAlign: pw.TextAlign.right)),
              pw.Padding(padding: cell, child: _name(store.item(l.itemId)?.unit ?? '')),
            ]),
        ],
      ),
      pw.SizedBox(height: 48),
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
        for (final s in ['Issued by (store keeper)', 'Received by'])
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
  final doc = pw.Document(theme: await _pdfTheme(), title: 'Invoice ${inv.no}');
  const cell = pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5);
  final bold = pw.TextStyle(fontWeight: pw.FontWeight.bold);
  final client = store.client(inv.clientId);
  const grey = pw.TextStyle(color: PdfColors.grey700);

  pw.Widget total(String label, String value, {bool strong = false}) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 3),
        child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
          pw.SizedBox(width: 120, child: pw.Text(label, style: strong ? bold : grey)),
          pw.SizedBox(width: 120, child: pw.Text(value, style: strong ? bold : null, textAlign: pw.TextAlign.right)),
        ]),
      );

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
      pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('INVOICE', style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0F766E))),
        _name(store.companyName.isEmpty ? ' ' : store.companyName, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
      ]),
      pw.Divider(color: PdfColors.grey400),
    ]),
    footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Invoice #${inv.no} · page ${c.pageNumber} of ${c.pagesCount}',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))),
    build: (_) => [
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Bill to', style: grey),
            _name(client?.name ?? '—', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            for (final x in [?client?.phone, ?client?.email, ?client?.address]) _name(x),
          ]),
        ),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('Invoice #${inv.no}', style: bold),
          pw.Text('Date: ${fmtDate(inv.date)}'),
          if (inv.dueDate != null) pw.Text('Pay by: ${fmtDate(inv.dueDate)}'),
        ]),
      ]),
      pw.SizedBox(height: 18),
      pw.Table(
        border: pw.TableBorder(horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: .5)),
        columnWidths: const {
          0: pw.FixedColumnWidth(24),
          1: pw.FlexColumnWidth(),
          2: pw.FixedColumnWidth(55),
          3: pw.FixedColumnWidth(90),
          4: pw.FixedColumnWidth(100),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            children: [
              for (final (i, h) in ['#', 'Description', 'Qty', 'Price', 'Amount'].indexed)
                pw.Padding(padding: cell, child: pw.Text(h, style: bold, textAlign: i >= 2 ? pw.TextAlign.right : null)),
            ],
          ),
          for (final (i, l) in inv.lines.indexed)
            pw.TableRow(children: [
              pw.Padding(padding: cell, child: pw.Text('${i + 1}')),
              pw.Padding(
                  padding: cell,
                  child: _name(l.itemId == null ? (l.description ?? '') : (store.item(l.itemId!)?.name ?? l.itemId!))),
              pw.Padding(padding: cell, child: pw.Text(fmtQty(l.qty), textAlign: pw.TextAlign.right)),
              pw.Padding(padding: cell, child: pw.Text(fmtQty(l.unitPrice), textAlign: pw.TextAlign.right)),
              pw.Padding(padding: cell, child: pw.Text(fmtQty(l.total), textAlign: pw.TextAlign.right)),
            ]),
        ],
      ),
      pw.SizedBox(height: 12),
      total('Subtotal', fmtMoney(inv.subtotal)),
      if (inv.discount != 0) total('Discount', '-${fmtMoney(inv.discount)}'),
      total('Total', fmtMoney(inv.total), strong: true),
      if (inv.paid > 0) total('Paid', fmtMoney(inv.paid)),
      if (inv.paid > 0) total('Balance due', fmtMoney(inv.balance), strong: true),
      if (inv.note != null) ...[pw.SizedBox(height: 18), _name(inv.note!)],
      pw.SizedBox(height: 30),
      pw.Text('Thank you for your business.', style: grey),
    ],
  ));
  return doc.save();
}

Future<void> shareInvoicePdf(WarehouseStore store, Invoice inv) => Printing.layoutPdf(
      name: 'Invoice-${inv.no}.pdf',
      onLayout: (_) => buildInvoicePdf(store, inv),
    );
