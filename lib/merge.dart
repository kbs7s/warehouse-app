import 'dart:convert';

/// Three-way merge of two edited copies of the data (backup JSON shape) that started from [base].
///
/// Used when two devices saved changes at the same time, or one worked offline. Every record that
/// only one side changed keeps that change. When both sides changed the same record, [local] wins.
/// When both sides added a record with the same number (two new issues both numbered 20), the
/// local one is given the next free number so neither is lost.
Map<String, dynamic> mergeData(Map<String, dynamic> base, Map<String, dynamic> local, Map<String, dynamic> remote) {
  final out = <String, dynamic>{...remote};
  for (final k in {...local.keys, ...remote.keys}) {
    if (k == 'savedAt') continue;
    final key = _keys[k];
    if (key != null) {
      out[k] = _mergeRecords(_list(base[k]), _list(local[k]), _list(remote[k]), key, numbered: _numbered.contains(k));
    } else if (_stringLists.contains(k)) {
      out[k] = _mergeStrings(_strings(base[k]), _strings(local[k]), _strings(remote[k]));
    } else {
      out[k] = _same(local[k], base[k]) ? remote[k] : local[k];
    }
  }
  out['savedAt'] = DateTime.now().toIso8601String();
  return out;
}

String _json(Object? v) => jsonEncode(v);
bool _same(Object? a, Object? b) => _json(a) == _json(b);

const _stringLists = {'departments', 'suppliers'};
const _numbered = {'receipts', 'purchases', 'payments', 'invoices', 'transfers'};

/// What identifies a record in each list. Lists without a natural id use the whole record.
final Map<String, String Function(Map<String, dynamic>)> _keys = {
  'items': (r) => '${r['id']}',
  'customers': (r) => '${r['name']}',
  'receipts': (r) => '${r['no']}',
  'transfers': (r) => '${r['no']}',
  'purchases': (r) => '${r['no']}',
  'payments': (r) => '${r['no']}',
  'invoices': (r) => '${r['no']}',
  'clients': (r) => '${r['id']}',
  'expenses': (r) => '${r['id']}',
  'monthCloses': (r) => '${r['from']}',
  'equipment': (r) => '${r['name']}',
  'history': _json,
};

List<Map<String, dynamic>> _list(Object? v) => [for (final e in (v as List? ?? const [])) e as Map<String, dynamic>];
List<String> _strings(Object? v) => [for (final e in (v as List? ?? const [])) '$e'];

List<Map<String, dynamic>> _mergeRecords(List<Map<String, dynamic>> base, List<Map<String, dynamic>> local,
    List<Map<String, dynamic>> remote, String Function(Map<String, dynamic>) key,
    {bool numbered = false}) {
  Map<String, Map<String, dynamic>> byKey(List<Map<String, dynamic>> l) => {for (final r in l) key(r): r};
  final b = byKey(base), l = byKey(local), r = byKey(remote);
  final out = <String, Map<String, dynamic>>{};
  final renumber = <Map<String, dynamic>>[];
  // Remote order first, then records only this device has.
  for (final k in [...r.keys, ...l.keys.where((k) => !r.containsKey(k))]) {
    final bv = b[k], lv = l[k], rv = r[k];
    if (_same(lv, bv)) {
      if (rv != null) out[k] = rv; // only remote changed (or nothing), including remote deletes
    } else if (_same(rv, bv)) {
      if (lv != null) out[k] = lv; // only this device changed, including local deletes
    } else if (lv == null || rv == null) {
      out[k] = (lv ?? rv)!; // deleted on one side, edited on the other: keep the edit
    } else if (numbered && bv == null && !_same(lv, rv)) {
      out[k] = rv; // both added a record with this number
      renumber.add(lv);
    } else {
      out[k] = lv;
    }
  }
  final result = out.values.toList();
  if (renumber.isNotEmpty) {
    var next = result.fold<int>(0, (m, e) => (e['no'] as num).toInt() > m ? (e['no'] as num).toInt() : m);
    for (final e in renumber) {
      result.add({...e, 'no': ++next});
    }
  }
  return result;
}

List<String> _mergeStrings(List<String> base, List<String> local, List<String> remote) {
  final removed = {...base.where((s) => !local.contains(s) || !remote.contains(s))};
  final out = <String>[];
  for (final s in [...remote, ...local]) {
    if (out.contains(s)) continue;
    final added = !base.contains(s);
    if (added || !removed.contains(s)) out.add(s);
  }
  return out;
}
