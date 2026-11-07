import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_app/changes.dart';

void main() {
  Map<String, dynamic> base() => {
        'items': [
          {'id': 'P001', 'name': 'Gloves', 'unit': 'box', 'openingQty': 10},
          {'id': 'P002', 'name': 'Masks', 'unit': 'box', 'openingQty': 5},
        ],
        'departments': ['ICU'],
        'receipts': [
          {'no': 1, 'department': 'ICU', 'lines': [{'itemId': 'P001', 'qty': 1}]},
        ],
        'purchases': <dynamic>[],
        'companyName': 'Store',
      };

  test('lists issues, purchases, items and departments with who made them', () {
    final after = base()
      ..['receipts'] = [
        {'no': 1, 'department': 'ICU', 'lines': [{'itemId': 'P001', 'qty': 2}]},
        {'no': 2, 'department': 'NICU', 'by': 'Ali', 'lines': [{'itemId': 'P001', 'qty': 1}, {'itemId': 'P002', 'qty': 3}]},
      ]
      ..['purchases'] = [
        {'no': 7, 'supplier': 'Al-Noor', 'lines': [{'itemId': 'P002', 'qty': 50}]},
      ]
      ..['items'] = [
        {'id': 'P001', 'name': 'Gloves', 'unit': 'box', 'openingQty': 10, 'minLevel': 4},
        {'id': 'P002', 'name': 'Masks', 'unit': 'box', 'openingQty': 5},
        {'id': 'P003', 'name': 'Gauze', 'unit': 'roll', 'openingQty': 0},
      ]
      ..['departments'] = ['ICU', 'NICU']
      ..['companyName'] = 'Hospital store';
    final c = findChanges(base(), after, by: 'Karar');
    final en = [for (final x in c) x.en];
    expect(en, containsAll([
      'Issue #1 edited',
      'Issue #2 to NICU · 2 items',
      'Purchase #7 from Al-Noor · 1 item',
      'Item edited: Gloves',
      'New item: Gauze',
      'Department added: NICU',
      'Store settings changed',
    ]));
    expect(c.firstWhere((x) => x.en.startsWith('Issue #2')).by, 'Ali'); // the record's own author
    expect(c.firstWhere((x) => x.en.startsWith('Issue #1')).by, 'Karar'); // the last saver
    expect(c.firstWhere((x) => x.en.startsWith('Issue #2')).ar, 'وصل صرف رقم 2 إلى NICU · 2 مواد');
  });

  test('deleted issues and a month close are listed; nothing changed lists nothing', () {
    expect(findChanges(base(), base()), isEmpty);
    final after = base()
      ..['receipts'] = <dynamic>[]
      ..['monthCloses'] = [
        {'from': '2026-10-01', 'to': '2026-10-31'},
      ];
    expect([for (final x in findChanges(base(), after)) x.en], ['Issue #1 deleted', 'Month closed (10/2026)']);
  });

  test('expiry dates that came with a purchase are not listed again', () {
    final after = base()
      ..['purchases'] = [
        {'no': 1, 'supplier': 'S', 'lines': [{'itemId': 'P001', 'qty': 5, 'expiry': '2027-01-01'}]},
      ]
      ..['items'] = [
        {'id': 'P001', 'name': 'Gloves', 'unit': 'box', 'openingQty': 10, 'expiries': [{'date': '2027-01-01', 'qty': 5}]},
        {'id': 'P002', 'name': 'Masks', 'unit': 'box', 'openingQty': 5},
      ];
    expect([for (final x in findChanges(base(), after)) x.en], ['Purchase #1 from S · 1 item']);
    after['purchases'] = <dynamic>[];
    expect([for (final x in findChanges(base(), after)) x.en], ['Expiry dates updated: Gloves']);
  });

  test('a saved change reads back the same', () {
    final c = findChanges(base(), base()..['departments'] = ['ICU', 'ER'], by: 'Ali').single;
    final back = StoreChange.fromJson(c.toJson());
    expect((back.en, back.ar, back.by, back.kind), (c.en, c.ar, c.by, ChangeKind.department));
  });
}
