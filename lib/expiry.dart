import 'l10n.dart';
import 'models.dart';
import 'store.dart';
import 'ui.dart' show fmtDate, fmtQty, todayIso;

enum ExpiryLevel { expired, soon, coming, later }

/// One expiry date of one item, with how many days are left (negative once expired).
class ExpiryInfo {
  ExpiryInfo(this.item, this.batch, this.daysLeft, this.level);
  final Item item;
  final ExpiryBatch batch;
  final int daysLeft;
  final ExpiryLevel level;

  String get label => switch (level) {
        ExpiryLevel.expired => daysLeft == 0
            ? tx('Expires today', 'ينتهي اليوم')
            : tx('Expired ${-daysLeft} days ago', 'منتهي منذ ${-daysLeft} يوم'),
        _ => daysLeft == 0 ? tx('Expires today', 'ينتهي اليوم') : tx('$daysLeft days left', 'باقٍ $daysLeft يوم'),
      };
}

int _daysBetween(String from, String to) =>
    DateTime.parse('${to}T00:00:00Z').difference(DateTime.parse('${from}T00:00:00Z')).inDays;

extension ExpiryBook on WarehouseStore {
  /// Every expiry date entered, soonest first. Items with nothing in stock are left out unless [all].
  List<ExpiryInfo> expiryList({bool all = false, String? today}) {
    final t = today ?? todayIso();
    final out = <ExpiryInfo>[];
    for (final i in items) {
      if (!i.active || i.expiries.isEmpty) continue;
      if (!all && stock(i.id).total <= 0) continue;
      for (final b in i.expiries) {
        final d = _daysBetween(t, b.date);
        final level = d <= 0
            ? ExpiryLevel.expired
            : d <= 30
                ? ExpiryLevel.soon
                : d <= expiryWarnDays
                    ? ExpiryLevel.coming
                    : ExpiryLevel.later;
        out.add(ExpiryInfo(i, b, d, level));
      }
    }
    out.sort((a, b) => a.batch.date.compareTo(b.batch.date));
    return out;
  }

  /// Expired or expiring within the warning period: what needs action.
  List<ExpiryInfo> get expiryAlerts => [for (final e in expiryList()) if (e.level != ExpiryLevel.later) e];
}

/// "12 Mar 2027 · 40 · lot A12" for one batch.
String batchLine(ExpiryBatch b, String unit) =>
    [fmtDate(b.date), if (b.qty != null) '${fmtQty(b.qty!)} $unit'.trim(), if (b.lot != null && b.lot!.isNotEmpty) tx('lot ${b.lot}', 'تشغيلة ${b.lot}')].join(' · ');
