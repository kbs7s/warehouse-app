// Plain data classes for the warehouse. Everything round-trips through the
// backup JSON format (see toJson/fromJson), which is also what is stored on the iPad.

num _n(Object? v) => v is num ? v : 0;

class Item {
  Item({
    required this.id,
    required this.name,
    required this.unit,
    this.openingQty = 0,
    this.minLevel = 0,
    this.category,
    this.active = true,
    this.note,
    this.salePrice,
    this.openingUnitCost,
    List<ExpiryBatch>? expiries,
  }) : expiries = expiries ?? [];

  final String id;
  String name;
  String unit;
  num openingQty;
  num minLevel;
  String? category;
  bool active;
  String? note;
  num? salePrice; // usual selling price, suggested on invoices (IQD)
  num? openingUnitCost; // cost of each unit of opening stock; null = use the first purchase price
  List<ExpiryBatch> expiries; // expiry dates of the stock on hand, entered by hand

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'] as String,
        name: j['name'] as String,
        unit: (j['unit'] as String?) ?? '',
        openingQty: _n(j['openingQty']),
        minLevel: _n(j['minLevel']),
        category: j['category'] as String?,
        active: (j['active'] as bool?) ?? true,
        note: j['note'] as String?,
        salePrice: j['salePrice'] as num?,
        openingUnitCost: j['openingUnitCost'] as num?,
        expiries: [for (final e in (j['expiries'] as List? ?? [])) ExpiryBatch.fromJson(e as Map<String, dynamic>)],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'unit': unit,
        'openingQty': openingQty,
        'minLevel': minLevel,
        'category': category,
        'active': active,
        'note': note,
        'salePrice': salePrice,
        'openingUnitCost': openingUnitCost,
        if (expiries.isNotEmpty) 'expiries': [for (final e in expiries) e.toJson()],
      };
}

/// Part of an item's stock that expires on one date: how many (if known) and the lot number.
class ExpiryBatch {
  ExpiryBatch({required this.date, this.qty, this.lot});
  String date; // yyyy-MM-dd
  num? qty;
  String? lot;

  factory ExpiryBatch.fromJson(Map<String, dynamic> j) =>
      ExpiryBatch(date: j['date'] as String, qty: j['qty'] as num?, lot: j['lot'] as String?);
  Map<String, dynamic> toJson() => {'date': date, if (qty != null) 'qty': qty, if (lot != null) 'lot': lot};
}

class Customer {
  Customer({required this.name, this.department, this.phone});
  String name;
  String? department;
  String? phone;

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
      name: j['name'] as String, department: j['department'] as String?, phone: j['phone']?.toString());
  Map<String, dynamic> toJson() => {'name': name, 'department': department, 'phone': phone};
}

class ReceiptLine {
  ReceiptLine({required this.itemId, required this.qty});
  String itemId;
  num qty;

  factory ReceiptLine.fromJson(Map<String, dynamic> j) =>
      ReceiptLine(itemId: j['itemId'] as String, qty: _n(j['qty']));
  Map<String, dynamic> toJson() => {'itemId': itemId, 'qty': qty};
}

/// An issue of items from the store to a hospital department.
class Receipt {
  Receipt({required this.no, this.date, this.department, this.customer, this.note, List<ReceiptLine>? lines})
      : lines = lines ?? [];
  int no;
  String? date; // yyyy-MM-dd
  String? department;
  String? customer;
  String? note;
  List<ReceiptLine> lines;

  factory Receipt.fromJson(Map<String, dynamic> j) => Receipt(
        no: (j['no'] as num).toInt(),
        date: j['date'] as String?,
        department: j['department'] as String?,
        customer: j['customer'] as String?,
        note: j['note'] as String?,
        lines: [for (final l in (j['lines'] as List? ?? [])) ReceiptLine.fromJson(l as Map<String, dynamic>)],
      );
  Map<String, dynamic> toJson() => {
        'no': no,
        'date': date,
        'department': department,
        'customer': customer,
        'note': note,
        'lines': [for (final l in lines) l.toJson()],
      };
}

class PurchaseLine {
  PurchaseLine({required this.itemId, required this.qty, this.unitPrice, num? total, this.note})
      : total = total ?? (unitPrice ?? 0) * qty;
  String itemId;
  num qty;
  num? unitPrice; // IQD
  num total; // IQD
  String? note;

  factory PurchaseLine.fromJson(Map<String, dynamic> j) => PurchaseLine(
        itemId: j['itemId'] as String,
        qty: _n(j['qty']),
        unitPrice: j['unitPrice'] as num?,
        total: _n(j['total']),
        note: j['note'] as String?,
      );
  Map<String, dynamic> toJson() =>
      {'itemId': itemId, 'qty': qty, 'unitPrice': unitPrice, 'total': total, 'note': note};
}

/// Items bought from a supplier.
class Purchase {
  Purchase({required this.no, this.date, this.supplier, this.note, List<PurchaseLine>? lines})
      : lines = lines ?? [];
  int no;
  String? date;
  String? supplier;
  String? note;
  List<PurchaseLine> lines;

  num get total => lines.fold<num>(0, (s, l) => s + l.total);

  factory Purchase.fromJson(Map<String, dynamic> j) => Purchase(
        no: (j['no'] as num).toInt(),
        date: j['date'] as String?,
        supplier: j['supplier'] as String?,
        note: j['note'] as String?,
        lines: [for (final l in (j['lines'] as List? ?? [])) PurchaseLine.fromJson(l as Map<String, dynamic>)],
      );
  Map<String, dynamic> toJson() => {
        'no': no,
        'date': date,
        'supplier': supplier,
        'note': note,
        'lines': [for (final l in lines) l.toJson()],
      };
}

enum StockStatus { inStock, low, out }

class StockInfo {
  StockInfo(this.item, this.bought, this.issued, [this.sold = 0]);
  final Item item;
  final num bought;
  final num issued; // given to departments (internal use)
  final num sold; // on client invoices

  num get qty => item.openingQty + bought - issued - sold;

  // Same rule as the Excel ALL sheet: above minimum is in stock, 0 or less is out.
  StockStatus get status => qty <= 0
      ? StockStatus.out
      : qty > item.minLevel
          ? StockStatus.inStock
          : StockStatus.low;
}

/// A supplier invoice and how much of it has been paid (sheet تسديد).
class Payment {
  Payment({required this.no, this.supplier, this.date, this.amount = 0, this.paid = 0, this.details});
  int no;
  String? supplier;
  String? date;
  num amount;
  num paid;
  String? details;

  num get remaining => amount - paid;
  bool get settled => remaining <= 0;

  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
        no: (j['no'] as num).toInt(),
        supplier: j['supplier'] as String?,
        date: j['date'] as String?,
        amount: _n(j['amount']),
        paid: _n(j['paid']),
        details: j['details'] as String?,
      );
  Map<String, dynamic> toJson() =>
      {'no': no, 'supplier': supplier, 'date': date, 'amount': amount, 'paid': paid, 'details': details};
}

/// Durable surgery tools (sheet Store). Each use is recorded as a date.
class Equipment {
  Equipment({required this.name, this.dateReceived, this.startQty = 0, this.boughtQty = 0, List<String>? usageDates})
      : usageDates = usageDates ?? [];
  String name;
  String? dateReceived;
  num startQty;
  num boughtQty;
  List<String> usageDates;

  // Same as Excel: used = number of usage dates; now = start + bought - used.
  int get usedQty => usageDates.length;
  num get nowQty => startQty + boughtQty - usedQty;

  factory Equipment.fromJson(Map<String, dynamic> j) => Equipment(
        name: j['name'] as String,
        dateReceived: j['dateReceived'] as String?,
        startQty: _n(j['startQty']),
        boughtQty: _n(j['boughtQty']),
        usageDates: [for (final d in (j['usageDates'] as List? ?? [])) d as String],
      );
  Map<String, dynamic> toJson() =>
      {'name': name, 'dateReceived': dateReceived, 'startQty': startQty, 'boughtQty': boughtQty, 'usageDates': usageDates};
}

/// Monthly issued/stock figures typed into the Excel Year sheet (before the app existed).
class HistoryRow {
  HistoryRow({this.itemId, required this.itemName, this.unit, required this.month, this.issued = 0, this.stock = 0});
  final String? itemId;
  final String itemName;
  final String? unit;
  final String month; // yyyy-MM
  final num issued;
  final num stock;

  factory HistoryRow.fromJson(Map<String, dynamic> j) => HistoryRow(
        itemId: j['itemId'] as String?,
        itemName: j['itemName'] as String,
        unit: j['unit'] as String?,
        month: j['month'] as String,
        issued: _n(j['issued']),
        stock: _n(j['stock']),
      );
  Map<String, dynamic> toJson() =>
      {'itemId': itemId, 'itemName': itemName, 'unit': unit, 'month': month, 'issued': issued, 'stock': stock};
}

/// Someone you bill.
class Client {
  Client({required this.id, required this.name, this.phone, this.email, this.address, this.note});
  final String id;
  String name;
  String? phone;
  String? email;
  String? address;
  String? note;

  factory Client.fromJson(Map<String, dynamic> j) => Client(
        id: j['id'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        address: j['address'] as String?,
        note: j['note'] as String?,
      );
  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'phone': phone, 'email': email, 'address': address, 'note': note};
}

/// One line on an invoice: a stock item (itemId set, reduces stock) or a service (description only).
class InvoiceLine {
  InvoiceLine({this.itemId, this.description, required this.qty, required this.unitPrice});
  String? itemId;
  String? description;
  num qty;
  num unitPrice; // IQD

  num get total => qty * unitPrice;

  factory InvoiceLine.fromJson(Map<String, dynamic> j) => InvoiceLine(
        itemId: j['itemId'] as String?,
        description: j['description'] as String?,
        qty: _n(j['qty']),
        unitPrice: _n(j['unitPrice']),
      );
  Map<String, dynamic> toJson() => {'itemId': itemId, 'description': description, 'qty': qty, 'unitPrice': unitPrice};
}

/// Money received against an invoice.
class InvoicePayment {
  InvoicePayment({required this.date, required this.amount, this.method, this.note});
  String date;
  num amount;
  String? method; // cash, bank, ...
  String? note;

  factory InvoicePayment.fromJson(Map<String, dynamic> j) => InvoicePayment(
      date: j['date'] as String, amount: _n(j['amount']), method: j['method'] as String?, note: j['note'] as String?);
  Map<String, dynamic> toJson() => {'date': date, 'amount': amount, 'method': method, 'note': note};
}

enum InvoiceStatus { paid, partlyPaid, unpaid, overdue }

/// A bill sent to a client.
class Invoice {
  Invoice({
    required this.no,
    required this.date,
    this.dueDate,
    this.clientId,
    this.discount = 0,
    this.note,
    List<InvoiceLine>? lines,
    List<InvoicePayment>? payments,
  })  : lines = lines ?? [],
        payments = payments ?? [];
  int no;
  String date;
  String? dueDate;
  String? clientId;
  num discount; // IQD off the whole invoice
  String? note;
  List<InvoiceLine> lines;
  List<InvoicePayment> payments;

  num get subtotal => lines.fold<num>(0, (s, l) => s + l.total);
  num get total => subtotal - discount;
  num get paid => payments.fold<num>(0, (s, p) => s + p.amount);
  num get balance => total - paid;

  InvoiceStatus status(String today) {
    if (balance <= 0) return InvoiceStatus.paid;
    if (dueDate != null && dueDate!.compareTo(today) < 0) return InvoiceStatus.overdue;
    return paid > 0 ? InvoiceStatus.partlyPaid : InvoiceStatus.unpaid;
  }

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
        no: (j['no'] as num).toInt(),
        date: j['date'] as String,
        dueDate: j['dueDate'] as String?,
        clientId: j['clientId'] as String?,
        discount: _n(j['discount']),
        note: j['note'] as String?,
        lines: [for (final l in (j['lines'] as List? ?? [])) InvoiceLine.fromJson(l as Map<String, dynamic>)],
        payments: [for (final p in (j['payments'] as List? ?? [])) InvoicePayment.fromJson(p as Map<String, dynamic>)],
      );
  Map<String, dynamic> toJson() => {
        'no': no,
        'date': date,
        'dueDate': dueDate,
        'clientId': clientId,
        'discount': discount,
        'note': note,
        'lines': [for (final l in lines) l.toJson()],
        'payments': [for (final p in payments) p.toJson()],
      };
}

/// Money spent that is not stock: rent, salaries, transport, electricity...
class Expense {
  Expense({required this.id, required this.date, required this.category, required this.amount, this.note});
  final String id;
  String date;
  String category;
  num amount; // IQD
  String? note;

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
      id: j['id'] as String,
      date: j['date'] as String,
      category: j['category'] as String,
      amount: _n(j['amount']),
      note: j['note'] as String?);
  Map<String, dynamic> toJson() => {'id': id, 'date': date, 'category': category, 'amount': amount, 'note': note};
}
