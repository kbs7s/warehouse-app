import 'package:flutter/material.dart';

import 'insights.dart';
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
  const _Section(this.label, this.icon, this.selectedIcon, this.pages, {this.wideOnly = false});
  final String label;
  final IconData icon, selectedIcon;
  final List<(String, Widget Function(WarehouseStore, Shell))> pages;
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
    _Section('Home', Icons.space_dashboard_outlined, Icons.space_dashboard, [
      ('Home', (s, sh) => HomeScreen(store: s, shell: sh)),
    ]),
    _Section('Sales', Icons.receipt_long_outlined, Icons.receipt_long, [
      ('Invoices', (s, _) => InvoicesScreen(store: s)),
      ('Clients', (s, _) => ClientsScreen(store: s)),
    ]),
    _Section('Stock', Icons.inventory_2_outlined, Icons.inventory_2, [
      ('Items', (s, _) => StockScreen(store: s)),
      ('Purchases', (s, _) => PurchasesScreen(store: s)),
      ('Issues', (s, _) => ReceiptsScreen(store: s)),
      ('Reports', (s, _) => ReportsScreen(store: s)),
    ]),
    _Section('Money', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, [
      ('Profit', (s, _) => ProfitScreen(store: s)),
      ('Expenses', (s, _) => ExpensesScreen(store: s)),
      ('Supplier bills', (s, _) => PaymentsScreen(store: s)),
    ]),
    _Section('Assistant', Icons.auto_awesome_outlined, Icons.auto_awesome, [
      ('Assistant', (s, sh) => AssistantScreen(store: s, shell: sh)),
    ]),
    _Section('Equipment', Icons.medical_services_outlined, Icons.medical_services, [
      ('Equipment', (s, _) => EquipmentScreen(store: s)),
    ], wideOnly: true),
    _Section('Settings', Icons.settings_outlined, Icons.settings, [
      ('Settings', (s, _) => SettingsScreen(store: s)),
    ], wideOnly: true),
  ];

  @override
  void go(String section, [int page = 0]) => setState(() {
        _section = _sections.indexWhere((s) => s.label == section);
        _page[_section] = page;
      });

  @override
  void goInsight(InsightTarget t) => switch (t) {
        InsightTarget.invoices => go('Sales'),
        InsightTarget.stock || InsightTarget.items => go('Stock'),
        InsightTarget.money => go('Money'),
        InsightTarget.supplierBills => go('Money', 2),
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
      labels: [for (final p in sec.pages) p.$1],
      index: pageIdx,
      onSelect: (i) => setState(() => _page[_section] = i),
      child: ListenableBuilder(
        listenable: widget.store,
        builder: (_, _) => KeyedSubtree(
          key: ValueKey('$_section/$pageIdx'),
          child: sec.pages[pageIdx].$2(widget.store, this),
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
                          child: Text(widget.store.companyName.isEmpty ? 'My business' : widget.store.companyName,
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
