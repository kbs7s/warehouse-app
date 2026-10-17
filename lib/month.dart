import 'store.dart';
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

/// A closed month: the figures saved when "Start new month" was pressed. Later edits to receipts
/// or purchases do not change it.
class MonthClose {
  MonthClose({required this.from, required this.to, required this.closedAt, required this.rows, this.receipts = 0});
  final String from, to; // yyyy-MM-dd, both included
  final String closedAt;
  final int receipts; // issue receipts in the month
  final List<MonthRow> rows;

  num get issued => rows.fold<num>(0, (s, r) => s + r.issued);
  num get received => rows.fold<num>(0, (s, r) => s + r.received);

  Map<String, dynamic> toJson() =>
      {'from': from, 'to': to, 'closedAt': closedAt, 'receipts': receipts, 'rows': [for (final r in rows) r.toJson()]};
  factory MonthClose.fromJson(Map<String, dynamic> j) => MonthClose(
        from: j['from'] as String,
        to: j['to'] as String,
        closedAt: (j['closedAt'] as String?) ?? '',
        receipts: (j['receipts'] as num?)?.toInt() ?? 0,
        rows: [for (final r in (j['rows'] as List? ?? [])) MonthRow.fromJson(r as Map<String, dynamic>)],
      );
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
  /// A null [to] means up to any date.
  Map<String, num> issuedBetween(String from, [String? to]) {
    final out = <String, num>{};
    bool inside(String? d) => d != null && d.compareTo(from) >= 0 && (to == null || d.compareTo(to) <= 0);
    for (final r in receipts) {
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
    for (final inv in invoices) {
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
      receipts.where((r) => r.date != null && r.date!.compareTo(from) >= 0 && r.date!.compareTo(to) <= 0).length;

  /// Saves the open month (from its start to [to], default today) and starts a new one the next day.
  MonthClose closeMonth({String? to}) {
    final from = openMonthStart;
    final end = to ?? todayIso();
    final c = MonthClose(
      from: from,
      to: end,
      closedAt: DateTime.now().toIso8601String(),
      receipts: receiptsBetween(from, end),
      rows: monthRows(from, end),
    );
    setMonthBook([...monthCloses, c], null);
    return c;
  }

  /// Takes back the last close: its month is open again.
  void reopenLastMonth() {
    if (monthCloses.isEmpty) return;
    final last = monthCloses.last;
    setMonthBook(monthCloses.sublist(0, monthCloses.length - 1), last.from);
  }

  void setOpenMonthStart(String iso) => setMonthBook(monthCloses, iso);
}

/// Items with any movement first; used to hide idle rows by default.
bool rowMoved(MonthRow r) => r.received != 0 || r.issued != 0;
