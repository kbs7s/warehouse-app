import 'l10n.dart';
import 'models.dart';
import 'store.dart';
import 'ui.dart';

enum InsightLevel { urgent, warning, good, tip }

/// Where tapping an insight should take the user.
enum InsightTarget { invoices, stock, money, supplierBills, settings, items }

class Insight {
  Insight(this.level, this.title, this.detail, {this.target});
  final InsightLevel level;
  final String title;
  final String detail;
  final InsightTarget? target;
}

/// Plain-language observations worked out on the device (no internet needed).
/// Ordered most urgent first.
List<Insight> buildInsights(WarehouseStore s, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = isoDate(n);
  final out = <Insight>[];

  final overdue = s.overdue(today);
  if (overdue.isNotEmpty) {
    final total = overdue.fold<num>(0, (t, i) => t + i.balance);
    final names = {for (final i in overdue) s.client(i.clientId)?.name ?? tx('No client', 'بدون زبون')}.take(3).join(', ');
    out.add(Insight(InsightLevel.urgent, tx('${overdue.length} overdue ${overdue.length == 1 ? 'invoice' : 'invoices'}: ${fmtMoney(total)}',
            '${overdue.length} ${overdue.length == 1 ? 'فاتورة متأخرة' : 'فواتير متأخرة'}: ${fmtMoney(total)}'),
        tx('Past the due date and not fully paid ($names). A short reminder usually gets these paid.',
            'تجاوزت موعد الاستحقاق ولم تُدفع بالكامل ($names). تذكير قصير عادةً يكفي لتحصيلها.'),
        target: InsightTarget.invoices));
  }

  final short = s.ledger.shortfall.keys.where((id) => s.item(id)?.active ?? false).toList();
  if (short.isNotEmpty) {
    out.add(Insight(InsightLevel.warning, tx('${short.length} items went below zero', '${short.length} مواد نزلت تحت الصفر'),
        tx(
            'More was given out than was ever recorded coming in (${short.take(3).map((id) => s.item(id)?.name ?? id).join('، ')}). '
                'A purchase is probably missing, so profit for these items is estimated.',
            'صُرف أكثر مما سُجّل دخوله (${short.take(3).map((id) => s.item(id)?.name ?? id).join('، ')}). '
                'غالباً هناك شراء غير مسجّل، لذا ربح هذه المواد تقديري.'),
        target: InsightTarget.stock));
  }

  final out0 = s.stockList.where((x) => x.status == StockStatus.out).length;
  final low = s.stockList.where((x) => x.status == StockStatus.low).length;
  if (out0 + low > 0) {
    out.add(Insight(InsightLevel.warning, tx('Reorder soon: $low low, $out0 out of stock', 'أعد الطلب قريباً: $low منخفض، $out0 نفد'),
        tx('These items are at or under the minimum level you set.', 'هذه المواد عند الحد الأدنى الذي حددته أو أقل.'), target: InsightTarget.stock));
  }

  if (s.weOwe > 0) {
    out.add(Insight(InsightLevel.tip, tx('You owe suppliers ${fmtMoney(s.weOwe)}', 'عليك للمجهزين ${fmtMoney(s.weOwe)}'),
        tx('Unpaid supplier bills. Plan these payments against the money clients owe you (${fmtMoney(s.owedToUs)}).',
            'فواتير مجهزين غير مدفوعة. خطط لدفعها مقابل ما على الزبائن لك (${fmtMoney(s.owedToUs)}).'),
        target: InsightTarget.supplierBills));
  }

  final (tf, tt) = Period.thisMonth.range(n);
  final (lf, lt) = Period.lastMonth.range(n);
  final thisM = s.profit(tf, tt), lastM = s.profit(lf, lt);
  if (thisM.sales > 0 || lastM.sales > 0) {
    final up = thisM.profit >= lastM.profit;
    out.add(Insight(up ? InsightLevel.good : InsightLevel.warning,
        tx('Profit this month: ${fmtMoney(thisM.profit)} (${up ? 'up' : 'down'} from ${fmtMoney(lastM.profit)} last month)',
            'ربح هذا الشهر: ${fmtMoney(thisM.profit)} (${up ? 'أعلى' : 'أقل'} من ${fmtMoney(lastM.profit)} الشهر الماضي)'),
        thisM.sales == 0
            ? tx('No sales invoiced yet this month.', 'لا توجد مبيعات مفوترة هذا الشهر بعد.')
            : tx('You keep ${(thisM.margin * 100).toStringAsFixed(0)} of every 100 IQD you sell after all costs.',
                'يبقى لك ${(thisM.margin * 100).toStringAsFixed(0)} من كل 100 $currency تبيعها بعد كل التكاليف.'),
        target: InsightTarget.money));
    if (thisM.sales > 0 && thisM.margin < .1) {
      out.add(Insight(InsightLevel.warning, tx('Thin margin this month', 'هامش ربح ضعيف هذا الشهر'),
          tx('Less than 10% of sales is left as profit. Check selling prices against item costs.',
              'أقل من 10% من المبيعات يبقى ربحاً. راجع أسعار البيع مقابل كلفة المواد.'), target: InsightTarget.money));
    }
  }

  if (thisM.expensesByCategory.isNotEmpty) {
    final top = thisM.expensesByCategory.entries.reduce((a, b) => a.value >= b.value ? a : b);
    out.add(Insight(InsightLevel.tip, tx('Biggest running cost this month: ${top.key}', 'أكبر مصروف تشغيلي هذا الشهر: ${top.key}'),
        tx('${fmtMoney(top.value)} of ${fmtMoney(thisM.expenses)} in expenses.', '${fmtMoney(top.value)} من ${fmtMoney(thisM.expenses)} مصاريف.'), target: InsightTarget.money));
  }

  final estimated = s.ledger.layers.values.expand((l) => l).where((l) => l.estimatedCost && l.unitCost == 0).length;
  if (estimated > 0) {
    out.add(Insight(InsightLevel.tip, tx('$estimated items have opening stock with no cost', '$estimated مواد لها رصيد افتتاحي بدون كلفة'),
        tx('Their stock value counts as zero. Add the cost per unit on each item so profit is accurate.',
            'قيمتها في المخزون تُحسب صفراً. أضف كلفة الوحدة لكل مادة ليكون الربح دقيقاً.'),
        target: InsightTarget.items));
  }

  final last = s.lastBackupAt == null ? null : DateTime.tryParse(s.lastBackupAt!);
  if (last == null || n.difference(last).inDays > 7) {
    out.add(Insight(InsightLevel.warning, last == null
            ? tx('No backup yet', 'لا توجد نسخة احتياطية بعد')
            : tx('Last backup ${n.difference(last).inDays} days ago', 'آخر نسخة احتياطية قبل ${n.difference(last).inDays} يوم'),
        tx('Your records live only on this device. Export a backup to Files or iCloud Drive.',
            'سجلاتك موجودة على هذا الجهاز فقط. صدّر نسخة احتياطية إلى Files أو iCloud Drive.'), target: InsightTarget.settings));
  }

  out.sort((a, b) => a.level.index.compareTo(b.level.index));
  return out;
}

/// A compact text snapshot of the business, given to the Claude assistant as context.
String businessSnapshot(WarehouseStore s, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final b = StringBuffer()
    ..writeln('Business: ${s.companyName.isEmpty ? '(unnamed)' : s.companyName}. Currency: IQD. Today: ${isoDate(n)}.');
  for (var i = 5; i >= 0; i--) {
    final from = DateTime(n.year, n.month - i), to = DateTime(n.year, n.month - i + 1, 0);
    final r = s.profit(isoDate(from), isoDate(to));
    b.writeln('Month ${isoDate(from).substring(0, 7)}: sales ${r.sales}, cost of goods sold ${r.costOfSales}, '
        'supplies used internally ${r.suppliesUsed}, expenses ${r.expenses} ${r.expensesByCategory}, profit ${r.profit}, cash received ${r.received}.');
  }
  b.writeln('Stock value now (FIFO): ${s.ledger.stockValue.round()}. Clients owe us: ${s.owedToUs}. We owe suppliers: ${s.weOwe}.');
  b.writeln('Clients (name: balance owed, invoices):');
  for (final c in s.clients) {
    b.writeln('- ${c.name}: ${s.owedBy(c.id)}, ${s.invoicesOf(c.id).length} invoices');
  }
  final today = isoDate(n);
  b.writeln('Unpaid invoices (no, client, date, due, total, balance, status):');
  for (final i in s.invoices.where((i) => i.balance > 0)) {
    b.writeln('- #${i.no}, ${s.client(i.clientId)?.name}, ${i.date}, ${i.dueDate}, ${i.total}, ${i.balance}, ${i.status(today).name}');
  }
  b.writeln('Stock (code, name, unit, qty, min, FIFO value, status):');
  for (final st in s.stockList) {
    b.writeln('- ${st.item.id}, ${st.item.name}, ${st.item.unit}, ${st.qty}, ${st.item.minLevel}, '
        '${s.ledger.itemValue(st.item.id).round()}, ${st.status.name}');
  }
  b.writeln('Unpaid supplier bills: ${[for (final p in s.payments) if (p.remaining > 0) '${p.supplier} ${p.remaining}'].join('; ')}');
  return b.toString();
}
