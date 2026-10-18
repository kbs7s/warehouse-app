import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sembast/sembast.dart';

import 'ledger.dart';
import 'models.dart';
import 'month.dart';

/// Holds all warehouse data in memory and saves it to the device after every change.
///
/// The whole data set is small (a few hundred items and receipts), so it is stored as
/// one JSON document in the browser's IndexedDB via sembast. That document has the same
/// shape as a backup file, so backup and restore are just export and import of it.
class WarehouseStore extends ChangeNotifier {
  WarehouseStore(this._db);

  final Database? _db;
  static final _record = StoreRef<String, String>.main().record('warehouse');
  // Device-only settings (the interface language). Kept apart so they never go into backup files.
  static final _deviceRecord = StoreRef<String, String>.main().record('device');

  List<Item> items = [];
  List<String> departments = [];
  List<Customer> customers = [];
  List<String> suppliers = [];
  List<Receipt> receipts = [];
  List<Purchase> purchases = [];
  List<HistoryRow> history = []; // Excel Year sheet, read-only
  List<Equipment> equipment = [];
  List<Payment> payments = []; // supplier bills
  List<Client> clients = [];
  List<Invoice> invoices = [];
  List<Expense> expenses = [];
  List<MonthClose> monthCloses = []; // saved month ends, oldest first
  int expiryWarnDays = 90; // alert this many days before an expiry date
  String? monthStart; // start of the open month when set by hand (see openMonthStart)
  String companyName = '';
  String? source;
  String? lastBackupAt; // when a backup file was last exported
  String lang = 'en'; // interface language on this device: 'en' or 'ar'

  Map<String, StockInfo> _stock = {};
  Ledger ledger = Ledger.build(items: [], purchases: [], receipts: [], invoices: []);

  /// True once data has been loaded from a file or the user chose to start empty.
  bool started = false;

  /// Loads the data saved on this device, if any. The Excel data is not bundled with the app
  /// (it contains staff names and phone numbers); it is loaded once from a file instead.
  ///
  /// [legacy] is the first version's database. When this device has nothing saved yet, its data
  /// is copied in once; the old database itself is left as it was.
  Future<void> load({Database? legacy}) async {
    final saved = _db == null ? null : await _record.get(_db);
    if (saved != null) {
      applyJson(jsonDecode(saved) as Map<String, dynamic>, save: false);
    } else if (legacy != null) {
      final old = await _record.get(legacy);
      if (old != null) applyJson(jsonDecode(old) as Map<String, dynamic>);
    }
    final device = _db == null ? null : await _deviceRecord.get(_db);
    if (device != null) {
      final j = jsonDecode(device) as Map<String, dynamic>;
      lang = (j['lang'] as String?) ?? 'en';
    }
  }

  Future<void> setLang(String code) async {
    lang = code;
    await _saveDevice();
  }

  Future<void> _saveDevice() async {
    if (_db != null) await _deviceRecord.put(_db, jsonEncode({'lang': lang}));
    notifyListeners();
  }

  void startEmpty() => applyJson({'format': 'warehouse-backup', 'version': 1, 'source': 'Started empty'});

  /// Deletes everything on this device and goes back to the welcome screen.
  Future<void> eraseAll() async {
    if (_db != null) {
      await _record.delete(_db);
      await _deviceRecord.delete(_db);
    }
    items = [];
    departments = [];
    customers = [];
    suppliers = [];
    receipts = [];
    purchases = [];
    history = [];
    equipment = [];
    payments = [];
    clients = [];
    invoices = [];
    expenses = [];
    monthCloses = [];
    monthStart = null;
    expiryWarnDays = 90;
    companyName = '';
    source = null;
    lastBackupAt = null;
    started = false;
    _stock = {};
    notifyListeners();
  }

  void applyJson(Map<String, dynamic> j, {bool save = true}) {
    if (j['format'] != 'warehouse-backup') {
      throw const FormatException('This is not a warehouse backup file.');
    }
    List<Map<String, dynamic>> list(String k) => [for (final e in (j[k] as List? ?? [])) e as Map<String, dynamic>];
    items = list('items').map(Item.fromJson).toList();
    departments = [for (final d in (j['departments'] as List? ?? [])) d as String];
    customers = list('customers').map(Customer.fromJson).toList();
    suppliers = [for (final s in (j['suppliers'] as List? ?? [])) s as String];
    receipts = list('receipts').map(Receipt.fromJson).toList();
    purchases = list('purchases').map(Purchase.fromJson).toList();
    history = list('history').map(HistoryRow.fromJson).toList();
    equipment = list('equipment').map(Equipment.fromJson).toList();
    payments = list('payments').map(Payment.fromJson).toList();
    clients = list('clients').map(Client.fromJson).toList();
    invoices = list('invoices').map(Invoice.fromJson).toList();
    expenses = list('expenses').map(Expense.fromJson).toList();
    monthCloses = list('monthCloses').map(MonthClose.fromJson).toList();
    monthStart = j['monthStart'] as String?;
    expiryWarnDays = (j['expiryWarnDays'] as num?)?.toInt() ?? 90;
    companyName = (j['companyName'] as String?) ?? '';
    source = j['source'] as String?;
    lastBackupAt = j['lastBackupAt'] as String?;
    started = true;
    _changed(save: save);
  }

  Map<String, dynamic> toJson() => {
        'format': 'warehouse-backup',
        'version': 2,
        'companyName': companyName,
        'source': source,
        'lastBackupAt': lastBackupAt,
        'savedAt': DateTime.now().toIso8601String(),
        'items': [for (final i in items) i.toJson()],
        'departments': departments,
        'customers': [for (final c in customers) c.toJson()],
        'suppliers': suppliers,
        'receipts': [for (final r in receipts) r.toJson()],
        'purchases': [for (final p in purchases) p.toJson()],
        'history': [for (final h in history) h.toJson()],
        'equipment': [for (final e in equipment) e.toJson()],
        'payments': [for (final p in payments) p.toJson()],
        'clients': [for (final c in clients) c.toJson()],
        'invoices': [for (final i in invoices) i.toJson()],
        'expenses': [for (final e in expenses) e.toJson()],
        'monthCloses': [for (final m in monthCloses) m.toJson()],
        'monthStart': monthStart,
        'expiryWarnDays': expiryWarnDays,
      };

  void _changed({bool save = true}) {
    final bought = <String, num>{};
    final issued = <String, num>{};
    for (final p in purchases) {
      for (final l in p.lines) {
        bought[l.itemId] = (bought[l.itemId] ?? 0) + l.qty;
      }
    }
    for (final r in receipts) {
      for (final l in r.lines) {
        issued[l.itemId] = (issued[l.itemId] ?? 0) + l.qty;
      }
    }
    final sold = <String, num>{};
    for (final inv in invoices) {
      for (final l in inv.lines) {
        if (l.itemId != null) sold[l.itemId!] = (sold[l.itemId!] ?? 0) + l.qty;
      }
    }
    _stock = {for (final i in items) i.id: StockInfo(i, bought[i.id] ?? 0, issued[i.id] ?? 0, sold[i.id] ?? 0)};
    ledger = Ledger.build(items: items, purchases: purchases, receipts: receipts, invoices: invoices);
    if (save && _db != null) _record.put(_db, jsonEncode(toJson()));
    notifyListeners();
  }

  /// Adds an expiry date to an item, or replaces [replacing] with it; null [batch] removes [replacing].
  void saveExpiry(String itemId, ExpiryBatch? batch, {ExpiryBatch? replacing}) {
    final it = item(itemId);
    if (it == null) return;
    if (replacing != null) it.expiries.remove(replacing);
    if (batch != null) it.expiries.add(batch);
    it.expiries.sort((a, b) => a.date.compareTo(b.date));
    _changed();
  }

  void setExpiryWarnDays(int days) {
    expiryWarnDays = days;
    _changed();
  }

  void setMonthBook(List<MonthClose> closes, String? start) {
    monthCloses = closes;
    monthStart = start;
    _changed();
  }

  // ---------- Queries ----------

  Item? item(String id) => items.where((i) => i.id == id).firstOrNull;
  StockInfo stock(String itemId) => _stock[itemId] ?? StockInfo(item(itemId) ?? Item(id: itemId, name: itemId, unit: ''), 0, 0);
  List<StockInfo> get stockList => [for (final i in items) if (i.active) _stock[i.id]!];
  List<Item> get activeItems => [for (final i in items) if (i.active) i];

  /// Every purchase and issue of one item, newest first.
  List<({String? date, String kind, String party, int no, num qty})> movements(String itemId) {
    final out = <({String? date, String kind, String party, int no, num qty})>[
      for (final p in purchases)
        for (final l in p.lines)
          if (l.itemId == itemId) (date: p.date, kind: 'Purchase', party: p.supplier ?? '', no: p.no, qty: l.qty),
      for (final r in receipts)
        for (final l in r.lines)
          if (l.itemId == itemId)
            (date: r.date, kind: 'Issue', party: r.department ?? '', no: r.no, qty: -l.qty),
      for (final inv in invoices)
        for (final l in inv.lines)
          if (l.itemId == itemId)
            (date: inv.date, kind: 'Invoice', party: client(inv.clientId)?.name ?? '', no: inv.no, qty: -l.qty),
    ];
    out.sort((a, b) => (b.date ?? '').compareTo(a.date ?? ''));
    return out;
  }

  int get nextReceiptNo => receipts.fold<int>(0, (m, r) => r.no > m ? r.no : m) + 1;
  int get nextPurchaseNo => purchases.fold<int>(0, (m, p) => p.no > m ? p.no : m) + 1;

  /// Next item code in the Excel style (P001, P003, ... stepping by 2).
  String get nextItemId {
    var max = 0;
    for (final i in items) {
      final m = RegExp(r'^P(\d+)$').firstMatch(i.id);
      if (m != null) max = int.parse(m.group(1)!) > max ? int.parse(m.group(1)!) : max;
    }
    return 'P${(max + 2).toString().padLeft(3, '0')}';
  }

  bool nameTaken(String name, {String? exceptId}) =>
      items.any((i) => i.id != exceptId && i.name.trim() == name.trim());

  // ---------- Changes ----------

  void markBackedUp() {
    lastBackupAt = DateTime.now().toIso8601String();
    _changed();
  }

  void saveItem(Item item) {
    final idx = items.indexWhere((i) => i.id == item.id);
    idx < 0 ? items.add(item) : items[idx] = item;
    _changed();
  }

  void saveReceipt(Receipt r, {int? replacingNo}) {
    receipts.removeWhere((x) => x.no == (replacingNo ?? r.no));
    receipts.add(r);
    receipts.sort((a, b) => a.no.compareTo(b.no));
    _remember(department: r.department, customer: r.customer);
    _changed();
  }

  void deleteReceipt(int no) {
    receipts.removeWhere((r) => r.no == no);
    _changed();
  }

  void savePurchase(Purchase p, {int? replacingNo}) {
    purchases.removeWhere((x) => x.no == (replacingNo ?? p.no));
    purchases.add(p);
    purchases.sort((a, b) => a.no.compareTo(b.no));
    final s = p.supplier?.trim();
    if (s != null && s.isNotEmpty && !suppliers.contains(s)) suppliers.add(s);
    _changed();
  }

  void deletePurchase(int no) {
    purchases.removeWhere((p) => p.no == no);
    _changed();
  }

  int get nextPaymentNo => payments.fold<int>(0, (m, p) => p.no > m ? p.no : m) + 1;

  void savePayment(Payment p, {int? replacingNo}) {
    payments.removeWhere((x) => x.no == (replacingNo ?? p.no));
    payments.add(p);
    payments.sort((a, b) => a.no.compareTo(b.no));
    final s = p.supplier?.trim();
    if (s != null && s.isNotEmpty && !suppliers.contains(s)) suppliers.add(s);
    _changed();
  }

  void deletePayment(int no) {
    payments.removeWhere((p) => p.no == no);
    _changed();
  }

  /// [index] null adds a new tool.
  void saveEquipment(Equipment e, {int? index}) {
    index == null ? equipment.add(e) : equipment[index] = e;
    _changed();
  }

  void deleteEquipment(int index) {
    equipment.removeAt(index);
    _changed();
  }

  // ---------- Reports ----------

  /// Quantity issued per item per month (yyyy-MM): app receipts, plus Excel history for months with no receipts.
  Map<String, Map<String, num>> monthlyIssued() {
    final out = <String, Map<String, num>>{};
    final appMonths = <String>{};
    for (final r in receipts) {
      if (r.date == null) continue;
      final m = r.date!.substring(0, 7);
      appMonths.add(m);
      for (final l in r.lines) {
        final row = out.putIfAbsent(l.itemId, () => {});
        row[m] = (row[m] ?? 0) + l.qty;
      }
    }
    for (final h in history) {
      if (h.itemId == null || appMonths.contains(h.month)) continue;
      final row = out.putIfAbsent(h.itemId!, () => {});
      row[h.month] = (row[h.month] ?? 0) + h.issued;
    }
    return out;
  }

  /// Quantity issued per department per item between two dates (inclusive, yyyy-MM-dd).
  Map<String, Map<String, num>> issuedByDepartment(String from, String to) {
    final out = <String, Map<String, num>>{};
    for (final r in receipts) {
      final d = r.date;
      if (d == null || d.compareTo(from) < 0 || d.compareTo(to) > 0) continue;
      final dept = out.putIfAbsent(r.department ?? '—', () => {});
      for (final l in r.lines) {
        dept[l.itemId] = (dept[l.itemId] ?? 0) + l.qty;
      }
    }
    return out;
  }

  // ---------- Billing ----------

  Client? client(String? id) => id == null ? null : clients.where((c) => c.id == id).firstOrNull;
  int get nextInvoiceNo => invoices.fold<int>(0, (m, i) => i.no > m ? i.no : m) + 1;
  String newId(String prefix) => '$prefix${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  void saveClient(Client c) {
    final i = clients.indexWhere((x) => x.id == c.id);
    i < 0 ? clients.add(c) : clients[i] = c;
    _changed();
  }

  /// Clients with invoices cannot be deleted (their history would be lost).
  bool deleteClient(String id) {
    if (invoices.any((i) => i.clientId == id)) return false;
    clients.removeWhere((c) => c.id == id);
    _changed();
    return true;
  }

  void saveInvoice(Invoice inv, {int? replacingNo}) {
    invoices.removeWhere((x) => x.no == (replacingNo ?? inv.no));
    invoices.add(inv);
    invoices.sort((a, b) => a.no.compareTo(b.no));
    _changed();
  }

  void deleteInvoice(int no) {
    invoices.removeWhere((i) => i.no == no);
    _changed();
  }

  void addInvoicePayment(int invoiceNo, InvoicePayment p) {
    invoices.firstWhere((i) => i.no == invoiceNo).payments.add(p);
    _changed();
  }

  List<Invoice> invoicesOf(String clientId) => [for (final i in invoices) if (i.clientId == clientId) i];
  num owedBy(String clientId) => invoicesOf(clientId).fold<num>(0, (s, i) => s + (i.balance > 0 ? i.balance : 0));
  num get owedToUs => invoices.fold<num>(0, (s, i) => s + (i.balance > 0 ? i.balance : 0));
  num get weOwe => payments.fold<num>(0, (s, p) => s + (p.remaining > 0 ? p.remaining : 0));
  List<Invoice> overdue(String today) => [for (final i in invoices) if (i.status(today) == InvoiceStatus.overdue) i];

  void saveExpense(Expense e) {
    final i = expenses.indexWhere((x) => x.id == e.id);
    i < 0 ? expenses.add(e) : expenses[i] = e;
    expenses.sort((a, b) => a.date.compareTo(b.date));
    _changed();
  }

  void deleteExpense(String id) {
    expenses.removeWhere((e) => e.id == id);
    _changed();
  }

  List<String> get expenseCategories {
    final seen = {for (final e in expenses) e.category};
    return {...seen, 'Rent', 'Salaries', 'Electricity', 'Transport', 'Maintenance', 'Other'}.toList();
  }

  void setCompanyName(String name) {
    companyName = name.trim();
    _changed();
  }

  /// Plain-words money summary for a period.
  ProfitReport profit(String from, String to) =>
      ledger.report(from: from, to: to, invoices: invoices, receipts: receipts, expenses: expenses);

  /// Cost of one invoice line's stock (0 for services).
  num invoiceLineCost(int invoiceNo, int line) => ledger.lineCost['inv:$invoiceNo:$line'] ?? 0;

  void _remember({String? department, String? customer}) {
    final d = department?.trim();
    if (d != null && d.isNotEmpty && !departments.contains(d)) departments.add(d);
    final c = customer?.trim();
    if (c != null && c.isNotEmpty && !customers.any((x) => x.name.trim() == c)) {
      customers.add(Customer(name: c, department: d));
    }
  }
}
