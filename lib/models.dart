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
  });

  final String id;
  String name;
  String unit;
  num openingQty;
  num minLevel;
  String? category;
  bool active;
  String? note;

  factory Item.fromJson(Map<String, dynamic> j) => Item(
        id: j['id'] as String,
        name: j['name'] as String,
        unit: (j['unit'] as String?) ?? '',
        openingQty: _n(j['openingQty']),
        minLevel: _n(j['minLevel']),
        category: j['category'] as String?,
        active: (j['active'] as bool?) ?? true,
        note: j['note'] as String?,
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
      };
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
  StockInfo(this.item, this.bought, this.issued);
  final Item item;
  final num bought;
  final num issued;

  num get qty => item.openingQty + bought - issued;

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
