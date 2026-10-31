import 'dart:convert';

import 'l10n.dart';

/// What kind of change, for the icon shown next to it.
enum ChangeKind { issue, purchase, move, item, month, department, other }

/// One change someone else made to the shared store, as shown in the Changes list.
class StoreChange {
  StoreChange({required this.at, required this.by, required this.kind, required this.en, required this.ar});
  final DateTime at;
  final String by; // who made it (name or email); empty when not known
  final ChangeKind kind;
  final String en, ar; // the same sentence in both languages, so a later language switch still reads well

  String get text => tx(en, ar);

  factory StoreChange.fromJson(Map<String, dynamic> j) => StoreChange(
        at: DateTime.parse(j['at'] as String),
        by: (j['by'] as String?) ?? '',
        kind: ChangeKind.values.asNameMap()[j['kind']] ?? ChangeKind.other,
        en: j['en'] as String,
        ar: j['ar'] as String,
      );
  Map<String, dynamic> toJson() => {'at': at.toIso8601String(), 'by': by, 'kind': kind.name, 'en': en, 'ar': ar};
}

/// The changes between two copies of the data (backup JSON shape): what others did to the shared
/// store since this device last saw it. Records that carry their own `by` are credited to that
/// person; everything else to [by], the last person who saved the online copy.
List<StoreChange> findChanges(Map<String, dynamic> before, Map<String, dynamic> after, {String by = '', DateTime? at}) {
  final when = at ?? DateTime.now();
  final out = <StoreChange>[];
  void add(ChangeKind kind, String en, String ar, [Map<String, dynamic>? record]) =>
      out.add(StoreChange(at: when, by: (record?['by'] as String?) ?? by, kind: kind, en: en, ar: ar));

  final names = {for (final i in _list(after['items'])) '${i['id']}': '${i['name']}'};
  for (final i in _list(before['items'])) {
    names.putIfAbsent('${i['id']}', () => '${i['name']}');
  }
  String item(Object? id) => names['$id'] ?? '$id';
  String n(int count, String one, String many) => count == 1 ? one : many;

  // Issues to departments.
  _diff(before['receipts'], after['receipts'], (r) => '${r['no']}',
      added: (r) {
        final lines = (r['lines'] as List? ?? const []).length;
        final dept = (r['department'] as String?) ?? '';
        add(ChangeKind.issue, 'Issue #${r['no']}${dept.isEmpty ? '' : ' to $dept'} · $lines ${n(lines, 'item', 'items')}',
            'وصل صرف رقم ${r['no']}${dept.isEmpty ? '' : ' إلى $dept'} · $lines ${n(lines, 'مادة', 'مواد')}', r);
      },
      edited: (r) => add(ChangeKind.issue, 'Issue #${r['no']} edited', 'تعديل وصل الصرف رقم ${r['no']}', r),
      removed: (r) => add(ChangeKind.issue, 'Issue #${r['no']} deleted', 'حذف وصل الصرف رقم ${r['no']}'));

  // Purchases.
  _diff(before['purchases'], after['purchases'], (p) => '${p['no']}',
      added: (p) {
        final lines = (p['lines'] as List? ?? const []).length;
        final sup = (p['supplier'] as String?) ?? '';
        add(ChangeKind.purchase, 'Purchase #${p['no']}${sup.isEmpty ? '' : ' from $sup'} · $lines ${n(lines, 'item', 'items')}',
            'شراء رقم ${p['no']}${sup.isEmpty ? '' : ' من $sup'} · $lines ${n(lines, 'مادة', 'مواد')}', p);
      },
      edited: (p) => add(ChangeKind.purchase, 'Purchase #${p['no']} edited', 'تعديل الشراء رقم ${p['no']}', p),
      removed: (p) => add(ChangeKind.purchase, 'Purchase #${p['no']} deleted', 'حذف الشراء رقم ${p['no']}'));

  // Moves between the main store and the reserve store.
  _diff(before['transfers'], after['transfers'], (t) => '${t['no']}',
      added: (t) => t['toReserve'] == true
          ? add(ChangeKind.move, 'Moved ${t['qty']} ${item(t['itemId'])} to the reserve store',
              'نقل ${t['qty']} ${item(t['itemId'])} إلى مخزن الاحتياط')
          : add(ChangeKind.move, 'Moved ${t['qty']} ${item(t['itemId'])} back to the main store',
              'إرجاع ${t['qty']} ${item(t['itemId'])} إلى المخزن الأساسي'),
      edited: (t) => add(ChangeKind.move, 'Move of ${item(t['itemId'])} edited', 'تعديل نقل ${item(t['itemId'])}'),
      removed: (t) => add(ChangeKind.move, 'Move of ${item(t['itemId'])} deleted', 'حذف نقل ${item(t['itemId'])}'));

  // Items. A purchase with expiry dates also updates its items' dates: that is part of the
  // purchase line above, so only expiry dates changed by hand are listed.
  final purchased = out.any((c) => c.kind == ChangeKind.purchase);
  final oldItems = {for (final i in _list(before['items'])) '${i['id']}': i};
  _diff(before['items'], after['items'], (i) => '${i['id']}',
      added: (i) => add(ChangeKind.item, 'New item: ${i['name']}', 'مادة جديدة: ${i['name']}'),
      edited: (i) {
        Map<String, dynamic> rest(Map<String, dynamic> m) => {...m}..remove('expiries');
        if (!_same(rest(oldItems['${i['id']}']!), rest(i))) {
          add(ChangeKind.item, 'Item edited: ${i['name']}', 'تعديل مادة: ${i['name']}');
        } else if (!purchased) {
          add(ChangeKind.item, 'Expiry dates updated: ${i['name']}', 'تحديث تواريخ الانتهاء: ${i['name']}');
        }
      },
      removed: (i) => add(ChangeKind.item, 'Item removed: ${i['name']}', 'حذف مادة: ${i['name']}'));

  // Month-end closes.
  _diff(before['monthCloses'], after['monthCloses'], (m) => '${m['from']}',
      added: (m) => add(ChangeKind.month, 'Month closed (${_month(m)})', 'إغلاق الشهر (${_month(m)})'),
      edited: (m) => add(ChangeKind.month, 'Month close edited (${_month(m)})', 'تعديل إغلاق الشهر (${_month(m)})'),
      removed: (m) => add(ChangeKind.month, 'Month reopened (${_month(m)})', 'إعادة فتح الشهر (${_month(m)})'));

  // Departments.
  final db = _strings(before['departments']), da = _strings(after['departments']);
  for (final d in da.where((d) => !db.contains(d))) {
    add(ChangeKind.department, 'Department added: $d', 'إضافة قسم: $d');
  }
  for (final d in db.where((d) => !da.contains(d))) {
    add(ChangeKind.department, 'Department removed: $d', 'حذف قسم: $d');
  }

  // Everything else, one line per part of the app that changed.
  const sections = <String, (String, String)>{
    'payments': ('Supplier payments changed', 'تغيير في تسديدات المجهزين'),
    'equipment': ('Surgery equipment changed', 'تغيير في معدات العمليات'),
    'stockCount': ('Stock count updated', 'تحديث جرد المخزون'),
    'reserveCount': ('Reserve count updated', 'تحديث جرد الاحتياط'),
    'invoices': ('Invoices changed', 'تغيير في الفواتير'),
    'clients': ('Clients changed', 'تغيير في الزبائن'),
    'expenses': ('Expenses changed', 'تغيير في المصاريف'),
    'customers': ('Staff names changed', 'تغيير في أسماء المستلمين'),
    'suppliers': ('Supplier list changed', 'تغيير في قائمة المجهزين'),
  };
  const handled = {'items', 'receipts', 'purchases', 'transfers', 'monthCloses', 'departments', 'history', 'savedAt', 'source', 'format', 'version'};
  var settings = false;
  for (final k in {...before.keys, ...after.keys}) {
    if (handled.contains(k) || _same(before[k], after[k])) continue;
    final s = sections[k];
    if (s != null) {
      add(ChangeKind.other, s.$1, s.$2);
    } else {
      settings = true;
    }
  }
  if (settings) add(ChangeKind.other, 'Store settings changed', 'تغيير في إعدادات المخزن');
  return out;
}

String _month(Map<String, dynamic> m) {
  final from = '${m['from']}';
  return from.length >= 7 ? '${int.tryParse(from.substring(5, 7)) ?? from.substring(5, 7)}/${from.substring(0, 4)}' : from;
}

void _diff(Object? before, Object? after, String Function(Map<String, dynamic>) key,
    {required void Function(Map<String, dynamic>) added,
    required void Function(Map<String, dynamic>) edited,
    required void Function(Map<String, dynamic>) removed}) {
  final b = {for (final r in _list(before)) key(r): r};
  final a = {for (final r in _list(after)) key(r): r};
  for (final e in a.entries) {
    final old = b[e.key];
    if (old == null) {
      added(e.value);
    } else if (!_same(old, e.value)) {
      edited(e.value);
    }
  }
  for (final e in b.entries) {
    if (!a.containsKey(e.key)) removed(e.value);
  }
}

List<Map<String, dynamic>> _list(Object? v) => [for (final e in (v as List? ?? const [])) e as Map<String, dynamic>];
List<String> _strings(Object? v) => [for (final e in (v as List? ?? const [])) '$e'];
bool _same(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);
