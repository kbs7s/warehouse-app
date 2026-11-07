import 'package:flutter/material.dart';

import '../changes.dart';
import '../l10n.dart';
import '../store.dart';
import '../sync.dart';
import '../ui.dart';

IconData changeIcon(ChangeKind k) => switch (k) {
      ChangeKind.issue => Icons.outbox_outlined,
      ChangeKind.purchase => Icons.shopping_cart_outlined,
      ChangeKind.move => Icons.swap_horiz,
      ChangeKind.item => Icons.inventory_2_outlined,
      ChangeKind.month => Icons.event_note_outlined,
      ChangeKind.department => Icons.apartment_outlined,
      ChangeKind.other => Icons.edit_note,
    };

String _clock(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// What others changed in the shared store, newest first.
class ChangesScreen extends StatefulWidget {
  const ChangesScreen({super.key, required this.store});
  final WarehouseStore store;

  @override
  State<ChangesScreen> createState() => _ChangesScreenState();
}

class _ChangesScreenState extends State<ChangesScreen> {
  late final int _newCount; // changes that were unread when the page opened, highlighted

  CloudSync? get _cloud => widget.store.cloud;

  @override
  void initState() {
    super.initState();
    _newCount = _cloud?.unread ?? 0;
    _cloud?.markRead();
  }

  @override
  Widget build(BuildContext context) {
    final c = _cloud;
    return Scaffold(
      appBar: AppBar(title: Text(tx('Changes', 'التغييرات'))),
      body: c == null
          ? const SizedBox.shrink()
          : ListenableBuilder(
              listenable: c,
              builder: (context, _) {
                final list = c.changes;
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.notifications_none,
                    title: tx('No changes yet', 'لا توجد تغييرات بعد'),
                    message: tx('When someone else issues supplies, records a purchase or edits an item, it shows here.',
                        'عندما يصرف شخص آخر مواد أو يسجل شراء أو يعدل مادة، يظهر ذلك هنا.'),
                  );
                }
                final t = Theme.of(context);
                final rows = <Widget>[];
                String? day;
                for (final (i, ch) in list.indexed) {
                  final d = isoDate(ch.at);
                  if (d != day) {
                    day = d;
                    rows.add(SectionTitle(d == todayIso() ? tx('Today', 'اليوم') : fmtDate(d)));
                  }
                  final fresh = i < _newCount;
                  rows.add(Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: fresh ? t.colorScheme.primaryContainer.withValues(alpha: .45) : null,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: t.colorScheme.secondaryContainer,
                        child: Icon(changeIcon(ch.kind), color: t.colorScheme.onSecondaryContainer, size: 20),
                      ),
                      title: NameText(ch.text, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text([if (ch.by.isNotEmpty) ch.by, _clock(ch.at)].join(' · ')),
                    ),
                  ));
                }
                return PageBody(maxWidth: 760, children: rows);
              },
            ),
    );
  }
}

/// Bell with the number of unread changes; opens the Changes page. Only for owners signed in to
/// the shared store.
class ChangesBell extends StatelessWidget {
  const ChangesBell({super.key, required this.store, this.color});
  final WarehouseStore store;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = store.cloud;
    if (c == null || !c.signedIn || c.isStaff) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => IconButton(
        tooltip: c.unread == 0
            ? tx('Changes', 'التغييرات')
            : tx('${c.unread} new changes', '${c.unread} تغييرات جديدة'),
        onPressed: () => openChanges(context, store),
        style: color == null ? null : IconButton.styleFrom(backgroundColor: color!.withValues(alpha: .14)),
        icon: Badge(
          isLabelVisible: c.unread > 0,
          label: Text(c.unread > 99 ? '99+' : '${c.unread}'),
          child: Icon(c.unread > 0 ? Icons.notifications : Icons.notifications_none, color: color),
        ),
      ),
    );
  }
}

void openChanges(BuildContext context, WarehouseStore store) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChangesScreen(store: store)));

/// The short notice shown when changes arrive from someone else.
String changesNotice(List<StoreChange> found) {
  final first = found.first;
  final who = first.by.isEmpty ? '' : '${first.by}: ';
  final more = found.length - 1;
  return '$who${first.text}${more > 0 ? tx(' (+$more more)', ' (+$more أخرى)') : ''}';
}
