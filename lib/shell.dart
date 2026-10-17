import 'package:flutter/material.dart';

import 'insights.dart';
import 'l10n.dart';
import 'screens/assistant_screen.dart';
import 'screens/client_screens.dart';
import 'screens/equipment_screen.dart';
import 'screens/expense_screens.dart';
import 'screens/home_screen.dart';
import 'screens/invoice_screens.dart';
import 'screens/payments_screen.dart';
import 'screens/profit_screen.dart';
import 'screens/purchase_screens.dart';
import 'screens/receipt_screens.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stock_screen.dart';
import 'store.dart';

/// Sub-page chips shown under a section's title (e.g. Invoices | Clients).
class SubNav extends InheritedWidget {
  const SubNav({super.key, required this.labels, required this.index, required this.onSelect, required super.child});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onSelect;

  /// The chips row for the current page's AppBar `bottom`, or null outside a section.
  static PreferredSizeWidget? bar(BuildContext context) {
    final nav = context.dependOnInheritedWidgetOfExactType<SubNav>();
    if (nav == null || nav.labels.length < 2) return null;
    return PreferredSize(
      preferredSize: const Size.fromHeight(52),
      child: SizedBox(
        height: 52,
        width: double.infinity,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            for (final (i, l) in nav.labels.indexed)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(l, style: const TextStyle(fontWeight: FontWeight.w600)),
                  selected: i == nav.index,
                  showCheckmark: false,
                  onSelected: (_) => nav.onSelect(i),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  @override
  bool updateShouldNotify(SubNav old) => old.index != index || old.labels != labels;
}

class _Section {
  const _Section(this.key, this.ar, this.icon, this.selectedIcon, this.pages, {this.wideOnly = false});
  /// Stable English name used by [Shell.go], whatever the interface language.
  final String key;
  final String ar;
  final IconData icon, selectedIcon;
  final List<(String, String, Widget Function(WarehouseStore, Shell))> pages;
  String get label => tx(key, ar);
  final bool wideOnly;
}

/// Lets screens jump to another section (e.g. the home screen's "Needs attention" list).
abstract class Shell {
  void go(String section, [int page = 0]);
  void goInsight(InsightTarget t);
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store});
  final WarehouseStore store;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> implements Shell {
  int _section = 0;
  final Map<int, int> _page = {};

  static final _sections = <_Section>[
    _Section('Home', 'الرئيسية', Icons.space_dashboard_outlined, Icons.space_dashboard, [
      ('Home', 'الرئيسية', (s, sh) => HomeScreen(store: s, shell: sh)),
    ]),
    _Section('Issue', 'الصرف', Icons.outbox_outlined, Icons.outbox, [
      ('Issues', 'وصولات الصرف', (s, _) => ReceiptsScreen(store: s)),
    ]),
    _Section('Stock', 'المخزون', Icons.inventory_2_outlined, Icons.inventory_2, [
      ('Items', 'المواد', (s, _) => StockScreen(store: s)),
      ('Reorder', 'إعادة الطلب', (s, _) => ReorderScreen(store: s)),
      ('Purchases', 'المشتريات', (s, _) => PurchasesScreen(store: s)),
      ('Reports', 'التقارير', (s, _) => ReportsScreen(store: s)),
    ]),
    _Section('Money', 'المالية', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, [
      ('Overview', 'نظرة عامة', (s, _) => ProfitScreen(store: s)),
      ('Invoices', 'الفواتير', (s, _) => InvoicesScreen(store: s)),
      ('Clients', 'الزبائن', (s, _) => ClientsScreen(store: s)),
      ('Expenses', 'المصاريف', (s, _) => ExpensesScreen(store: s)),
      ('Supplier bills', 'فواتير المجهزين', (s, _) => PaymentsScreen(store: s)),
    ]),
    _Section('Assistant', 'المساعد', Icons.auto_awesome_outlined, Icons.auto_awesome, [
      ('Assistant', 'المساعد', (s, sh) => AssistantScreen(store: s, shell: sh)),
    ]),
    _Section('Equipment', 'المعدات', Icons.medical_services_outlined, Icons.medical_services, [
      ('Equipment', 'المعدات', (s, _) => EquipmentScreen(store: s)),
    ], wideOnly: true),
    _Section('Settings', 'الإعدادات', Icons.settings_outlined, Icons.settings, [
      ('Settings', 'الإعدادات', (s, _) => SettingsScreen(store: s)),
    ], wideOnly: true),
  ];

  @override
  void go(String section, [int page = 0]) {
    final i = _sections.indexWhere((s) => s.key == section);
    // Phones have no tab for wide-only sections (Equipment, Settings): open them as a page instead.
    if (_sections[i].wideOnly && MediaQuery.sizeOf(context).width < 700) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ListenableBuilder(
              listenable: widget.store, builder: (_, _) => _sections[i].pages[page].$3(widget.store, this))));
      return;
    }
    setState(() {
      _section = i;
      _page[i] = page;
    });
  }

  @override
  void goInsight(InsightTarget t) => switch (t) {
        InsightTarget.invoices => go('Money', 1),
        InsightTarget.stock => go('Stock', 1),
        InsightTarget.items => go('Stock'),
        InsightTarget.money => go('Money'),
        InsightTarget.supplierBills => go('Money', 4),
        InsightTarget.settings => go('Settings'),
      };

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final phone = w < 700;
    final visible = [for (final (i, s) in _sections.indexed) if (!phone || !s.wideOnly) i];
    final sec = _sections[_section];
    final pageIdx = _page[_section] ?? 0;
    final body = SubNav(
      labels: [for (final p in sec.pages) tx(p.$1, p.$2)],
      index: pageIdx,
      onSelect: (i) => setState(() => _page[_section] = i),
      child: ListenableBuilder(
        listenable: widget.store,
        builder: (_, _) => KeyedSubtree(
          key: ValueKey('$_section/$pageIdx'),
          child: sec.pages[pageIdx].$3(widget.store, this),
        ),
      ),
    );

    if (phone) {
      final navIdx = visible.indexOf(_section);
      return Scaffold(
        body: body,
        bottomNavigationBar: navIdx < 0
            ? null
            : NavigationBar(
                selectedIndex: navIdx,
                height: 68,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                onDestinationSelected: (i) => setState(() => _section = visible[i]),
                destinations: [
                  for (final i in visible)
                    NavigationDestination(
                        icon: Icon(_sections[i].icon), selectedIcon: Icon(_sections[i].selectedIcon), label: _sections[i].label),
                ],
              ),
      );
    }

    final extended = w >= 1180;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Row(children: [
        NavigationRail(
          extended: extended,
          minExtendedWidth: 220,
          selectedIndex: _section,
          onDestinationSelected: (i) => setState(() => _section = i),
          labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
          leading: Padding(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 16),
            child: extended
                ? SizedBox(
                    width: 190,
                    child: Row(children: [
                      _Logo(color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(widget.store.companyName.isEmpty ? tx('My business', 'قسم التجهيز') : widget.store.companyName,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                              overflow: TextOverflow.ellipsis)),
                    ]),
                  )
                : _Logo(color: scheme.primary),
          ),
          destinations: [
            for (final s in _sections)
              NavigationRailDestination(icon: Icon(s.icon), selectedIcon: Icon(s.selectedIcon), label: Text(s.label)),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: body),
      ]),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.inventory_2, color: Colors.white, size: 20),
      );
}
