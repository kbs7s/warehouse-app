import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_app/merge.dart';

void main() {
  Map<String, dynamic> d({List<Map<String, dynamic>>? items, List<Map<String, dynamic>>? receipts, List<String>? deps, String name = 'A'}) => {
        'format': 'warehouse-backup',
        'companyName': name,
        'items': items ?? [],
        'receipts': receipts ?? [],
        'departments': deps ?? [],
      };
  Map<String, dynamic> item(String id, num min) => {'id': id, 'name': id, 'minLevel': min};
  Map<String, dynamic> rec(int no, String dep) => {'no': no, 'department': dep};

  test('keeps changes from both sides', () {
    final base = d(items: [item('A', 1), item('B', 1)], deps: ['ICU', 'ER']);
    final local = d(items: [item('A', 5), item('B', 1)], deps: ['ICU', 'ER', 'NICU'], name: 'Store');
    final remote = d(items: [item('A', 1), item('B', 7), item('C', 0)], deps: ['ICU']);
    final m = mergeData(base, local, remote);
    expect(m['items'], [item('A', 5), item('B', 7), item('C', 0)]);
    expect(m['departments'], ['ICU', 'NICU']);
    expect(m['companyName'], 'Store');
  });

  test('two new receipts with the same number both survive', () {
    final base = d(receipts: [rec(1, 'ICU')]);
    final local = d(receipts: [rec(1, 'ICU'), rec(2, 'ER')]);
    final remote = d(receipts: [rec(1, 'ICU'), rec(2, 'NICU'), rec(3, 'OR')]);
    final m = mergeData(base, local, remote);
    expect(m['receipts'], [rec(1, 'ICU'), rec(2, 'NICU'), rec(3, 'OR'), rec(4, 'ER')]);
  });

  test('a delete on one side and no change on the other removes it; an edit beats a delete', () {
    final base = d(receipts: [rec(1, 'ICU'), rec(2, 'ER')]);
    final local = d(receipts: [rec(2, 'ER')]);
    final remote = d(receipts: [rec(1, 'ICU'), rec(2, 'OR')]);
    expect(mergeData(base, local, remote)['receipts'], [rec(2, 'OR')]);
    final local2 = d(receipts: [rec(1, 'PEDS'), rec(2, 'ER')]);
    final remote2 = d(receipts: [rec(2, 'ER')]);
    expect(mergeData(base, local2, remote2)['receipts'], [rec(2, 'ER'), rec(1, 'PEDS')]);
  });
}
