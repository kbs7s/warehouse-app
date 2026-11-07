import 'models.dart';
import 'store.dart';
import 'l10n.dart';
import 'ui.dart' show isoDate, todayIso;

/// One item's figures for a month: what was there at the start, what came in, what went out
/// (issued to departments plus sold), and what was left at the end.
class MonthRow {
  MonthRow({required this.itemId, required this.name, required this.unit, required this.opening, required this.received, required this.issued});
  final String itemId, name, unit;
  final num opening, received, issued;
  num get closing => opening + received - issued;

  Map<String, dynamic> toJson() =>
      {'itemId': itemId, 'name': name, 'unit': unit, 'opening': opening, 'received': received, 'issued': issued};
  factory MonthRow.fromJson(Map<String, dynamic> j) => MonthRow(
        itemId: j['itemId'] as String,
        name: (j['name'] as String?) ?? j['itemId'] as String,
        unit: (j['unit'] as String?) ?? '',
        opening: (j['opening'] as num?) ?? 0,
        received: (j['received'] as num?) ?? 0,
        issued: (j['issued'] as num?) ?? 0,
      );
}

/// The monthly hospital figures asked for when a month is closed. Each can be left empty and
/// filled in later from the month's page.
const monthStatKeys = <(String, String, String)>[
  ('operations', 'Operations', 'العمليات'),
  ('cath', 'Catheterizations', 'عمليات القسطرة'),
  ('nicu', 'Premature (NICU) admissions', 'دخول الخدج'),
  ('insurance', 'Insurance admissions', 'دخول الضمان'),
];

/// A closed month: the figures saved when "Close month" was pressed. Later edits do not change it.
///
/// Months closed with a fresh start ([fresh]) also keep the month's own issues, purchases and
/// moves here: they leave the open lists, numbering starts again from 1, and every item's stock at
/// the close becomes its opening stock for the new month.
class MonthClose {
  MonthClose({
    required this.from,
    required this.to,
    required this.closedAt,
    required this.rows,
    this.receipts = 0,
    Map<String, num>? stats,
    this.fresh = false,
    List<Receipt>? issueList,
    List<Purchase>? purchaseList,
    List<Transfer>? transferList,
    Map<String, num>? reserveStart,
    Map<String, num>? reserveEnd,
    Map<String, List<num?>>? before,
  })  : stats = stats ?? {},
        issueList = issueList ?? [],
        purchaseList = purchaseList ?? [],
        transferList = transferList ?? [],
        reserveStart = reserveStart ?? {},
        reserveEnd = reserveEnd ?? {},
        before = before ?? {};
  final String from, to; // yyyy-MM-dd, both included
  final String closedAt;
  final int receipts; // issue receipts in the month
  final List<MonthRow> rows; // both stores together
  final Map<String, num> stats; // monthStatKeys -> number; missing = not filled in yet
  final bool fresh;
  final List<Receipt> issueList;
  final List<Purchase> purchaseList;
  final List<Transfer> transferList;
  final Map<String, num> reserveStart, reserveEnd; // reserve store per item at the start and end
  final Map<String, List<num?>> before; // item -> [openingQty, openingReserve, openingUnitCost] before the close, for reopening

  num get issued => rows.fold<num>(0, (s, r) => s + r.issued);
  num get received => rows.fold<num>(0, (s, r) => s + r.received);
  bool get statsMissing => monthStatKeys.any((k) => stats[k.$1] == null);

  Map<String, dynamic> toJson() => {
        'from': from,
        'to': to,
        'closedAt': closedAt,
        'receipts': receipts,
        'rows': [for (final r in rows) r.toJson()],
        if (stats.isNotEmpty) 'stats': stats,
        if (fresh) 'fresh': true,
        if (issueList.isNotEmpty) 'issueList': [for (final r in issueList) r.toJson()],
        if (purchaseList.isNotEmpty) 'purchaseList': [for (final p in purchaseList) p.toJson()],
        if (transferList.isNotEmpty) 'transferList': [for (final t in transferList) t.toJson()],
        if (reserveStart.isNotEmpty) 'reserveStart': reserveStart,
        if (reserveEnd.isNotEmpty) 'reserveEnd': reserveEnd,
        if (before.isNotEmpty) 'before': before,
      };
  factory MonthClose.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> list(String k) => [for (final e in (j[k] as List? ?? const [])) e as Map<String, dynamic>];
    Map<String, num> nums(String k) => {for (final e in ((j[k] as Map?) ?? const {}).entries) '${e.key}': e.value as num};
    return MonthClose(
      from: j['from'] as String,
      to: j['to'] as String,
      closedAt: (j['closedAt'] as String?) ?? '',
      receipts: (j['receipts'] as num?)?.toInt() ?? 0,
      rows: [for (final r in list('rows')) MonthRow.fromJson(r)],
      stats: nums('stats'),
      fresh: j['fresh'] == true,
      issueList: list('issueList').map(Receipt.fromJson).toList(),
      purchaseList: list('purchaseList').map(Purchase.fromJson).toList(),
      transferList: list('transferList').map(Transfer.fromJson).toList(),
      reserveStart: nums('reserveStart'),
      reserveEnd: nums('reserveEnd'),
      before: {
        for (final e in ((j['before'] as Map?) ?? const {}).entries)
          '${e.key}': [for (final v in e.value as List) v as num?]
      },
    );
  }
}

String _nextDay(String iso) {
  final d = DateTime.parse(iso);
  return isoDate(DateTime(d.year, d.month, d.day + 1));
}

extension MonthBook on WarehouseStore {
  /// First day of the month that is still open: the day after the last close, or the first of
  /// this calendar month before anything has been closed. Can be changed on the Month page.
  String get openMonthStart {
    if (monthStart != null) return monthStart!;
    if (monthCloses.isNotEmpty) return _nextDay(monthCloses.last.to);
    final n = DateTime.now();
    return isoDate(DateTime(n.year, n.month));
  }

  /// Quantity issued to departments (and sold) per item between two dates, both included.
  /// A null [to] means up to any date. Includes issues kept in closed months.
  Map<String, num> issuedBetween(String from, [String? to]) {
    final out = <String, num>{};
    bool inside(String? d) => d != null && d.compareTo(from) >= 0 && (to == null || d.compareTo(to) <= 0);
    for (final r in allReceipts) {
      if (!inside(r.date)) continue;
      for (final l in r.lines) {
        out[l.itemId] = (out[l.itemId] ?? 0) + l.qty;
      }
    }
    for (final inv in invoices) {
      if (!inside(inv.date)) continue;
      for (final l in inv.lines) {
        if (l.itemId != null) out[l.itemId!] = (out[l.itemId!] ?? 0) + l.qty;
      }
    }
    return out;
  }

  /// Spent (issued) in the open month, per item.
  Map<String, num> get spentThisMonth => issuedBetween(openMonthStart);

  /// Bought in the open month, per item.
  Map<String, num> get boughtThisMonth {
    final from = openMonthStart, out = <String, num>{};
    for (final p in allPurchases) {
      if ((p.date ?? '').compareTo(from) < 0) continue;
      for (final l in p.lines) {
        out[l.itemId] = (out[l.itemId] ?? 0) + l.qty;
      }
    }
    return out;
  }

  /// Spent (issued) since 1 January, per item.
  Map<String, num> get spentThisYear => issuedBetween('${DateTime.now().year}-01-01');

  /// Every active item's opening, received, issued and closing stock for the dates [from]..[to].
  /// Entries without a date count as before the month.
  List<MonthRow> monthRows(String from, String to) {
    final before = <String, num>{}, received = <String, num>{}, issued = <String, num>{};
    void add(Map<String, num> m, String id, num q) => m[id] = (m[id] ?? 0) + q;
    String? where(String? d) => d == null || d.compareTo(from) < 0 ? 'before' : (d.compareTo(to) <= 0 ? 'in' : null);
    for (final p in purchases) {
      final w = where(p.date);
      for (final l in p.lines) {
        if (w == 'before') add(before, l.itemId, l.qty);
        if (w == 'in') add(received, l.itemId, l.qty);
      }
    }
    void out(String? date, String id, num q) {
      final w = where(date);
      if (w == 'before') add(before, id, -q);
      if (w == 'in') add(issued, id, q);
    }
    for (final r in receipts) {
      for (final l in r.lines) {
        out(r.date, l.itemId, l.qty);
      }
    }
    for (final inv in liveInvoices) {
      for (final l in inv.lines) {
        if (l.itemId != null) out(inv.date, l.itemId!, l.qty);
      }
    }
    return [
      for (final i in items)
        if (i.active || received.containsKey(i.id) || issued.containsKey(i.id))
          MonthRow(
            itemId: i.id,
            name: i.name,
            unit: i.unit,
            opening: i.openingQty + (before[i.id] ?? 0),
            received: received[i.id] ?? 0,
            issued: issued[i.id] ?? 0,
          ),
    ];
  }

  int receiptsBetween(String from, String to) =>
      allReceipts.where((r) => r.date != null && r.date!.compareTo(from) >= 0 && r.date!.compareTo(to) <= 0).length;

  /// Reserve store per item counting only what happened on or before [end] (all when null), or,
  /// with [beforeDay], strictly before that day.
  Map<String, num> reserveAt({String? end, String? beforeDay}) {
    bool counts(String? d) =>
        beforeDay != null ? (d == null || d.compareTo(beforeDay) < 0) : (end == null || d == null || d.compareTo(end) <= 0);
    final out = <String, num>{for (final i in items) if (i.openingReserve != 0) i.id: i.openingReserve};
    void add(String id, num q) => out[id] = (out[id] ?? 0) + q;
    for (final t in transfers) {
      if (counts(t.date)) add(t.itemId, t.toReserve ? t.qty : -t.qty);
    }
    for (final p in purchases) {
      if (!p.toReserve || !counts(p.date)) continue;
      for (final l in p.lines) {
        add(l.itemId, l.qty);
      }
    }
    for (final r in receipts) {
      if (!r.fromReserve || !counts(r.date)) continue;
      for (final l in r.lines) {
        add(l.itemId, -l.qty);
      }
    }
    return out;
  }

  /// Saves the open month (from its start to [to], default today) and starts a new one the next day.
  ///
  /// The month's issues, purchases and moves are kept with the saved month and leave the open
  /// lists, so issue, purchase and move numbers start again from 1. Every item's stock at the close
  /// (in both stores) becomes its opening stock, and the month's spend starts again from zero.
  /// Purchases still owed to a supplier are carried over as an older bill, so the debt stays.
  MonthClose closeMonth({String? to, Map<String, num>? stats}) {
    final from = openMonthStart;
    final end = to ?? todayIso();
    bool inMonth(String? d) => d == null || d.compareTo(end) <= 0;
    final rows = monthRows(from, end);
    final closing = {for (final r in rows) r.itemId: r.closing};
    // Items left out of the rows (inactive and unmoved) keep their stock too.
    final before = monthRows('0000-01-01', end);
    for (final r in before) {
      closing.putIfAbsent(r.itemId, () => r.closing);
    }
    final resStart = reserveAt(beforeDay: from), resEnd = reserveAt(end: end);
    final keptIssues = [for (final r in receipts) if (inMonth(r.date)) r];
    final keptPurchases = [for (final p in purchases) if (inMonth(p.date)) p];
    final keptMoves = [for (final t in transfers) if (inMonth(t.date)) t];

    final c = MonthClose(
      from: from,
      to: end,
      closedAt: DateTime.now().toIso8601String(),
      receipts: receiptsBetween(from, end),
      rows: rows,
      stats: {...?stats},
      fresh: true,
      issueList: keptIssues,
      purchaseList: keptPurchases,
      transferList: keptMoves,
      reserveStart: {for (final e in resStart.entries) if (e.value != 0) e.key: e.value},
      reserveEnd: {for (final e in resEnd.entries) if (e.value != 0) e.key: e.value},
      before: {for (final i in items) i.id: [i.openingQty, i.openingReserve, i.openingUnitCost]},
    );
    startFreshMonth(c, closing: closing, reserve: resEnd);
    return c;
  }

  /// Why the last closed month cannot be reopened, or null when it can.
  String? reopenBlocker() {
    if (monthCloses.isEmpty) return '';
    final last = monthCloses.last;
    if (!last.fresh) return null;
    final n = receipts.length + purchases.length + transfers.length;
    if (n > 0) {
      return tx('Issues, purchases or moves have been recorded since this month was closed. Reopening would mix the two months.',
          'سُجّل صرف أو شراء أو نقل بعد إغلاق هذا الشهر. إعادة فتحه ستخلط الشهرين.');
    }
    final carried = payments.where((b) => b.carriedFrom == last.from).fold<num>(0, (a, b) => a + b.paid);
    final paidThen = last.purchaseList.where((p) => p.owed > 0).fold<num>(0, (a, p) => a + p.paid);
    if (carried != paidThen) {
      return tx('A payment was recorded against this month\'s purchases after it was closed.',
          'سُجّلت دفعة على مشتريات هذا الشهر بعد إغلاقه.');
    }
    return null;
  }

  /// Takes back the last close: its month is open again, with its issues, purchases and moves.
  void reopenLastMonth() {
    if (monthCloses.isEmpty || reopenBlocker() != null) return;
    final last = monthCloses.last;
    if (last.fresh) {
      undoFreshMonth(last);
    } else {
      setMonthBook(monthCloses.sublist(0, monthCloses.length - 1), last.from);
    }
  }

  /// Fills in or changes a closed month's figures (operations, catheterizations, ...).
  void setMonthStats(MonthClose m, Map<String, num> stats) {
    m.stats
      ..clear()
      ..addAll(stats);
    setMonthBook(monthCloses, monthStart);
  }

  void setOpenMonthStart(String iso) => setMonthBook(monthCloses, iso);
}

/// Items with any movement first; used to hide idle rows by default.
bool rowMoved(MonthRow r) => r.received != 0 || r.issued != 0;
