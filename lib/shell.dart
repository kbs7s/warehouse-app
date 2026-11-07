import 'package:flutter/material.dart';

import 'insights.dart';
import 'l10n.dart';
import 'changes.dart';
import 'screens/changes_screen.dart';
import 'screens/client_screens.dart';
import 'screens/cloud_screens.dart';
import 'screens/count_screen.dart';
import 'screens/departments_screen.dart';
import 'screens/equipment_screen.dart';
import 'screens/expense_screens.dart';
import 'screens/expiry_screens.dart';
import 'screens/home_screen.dart';
import 'screens/invoice_screens.dart';
import 'screens/month_screen.dart';
import 'screens/payments_screen.dart';
import 'screens/profit_screen.dart';
import 'screens/purchase_screens.dart';
import 'screens/receipt_screens.dart';
import 'screens/reports_screen.dart';
import 'screens/reserve_screens.dart';
import 'screens/settings_screen.dart';
import 'screens/stock_screen.dart';
import 'screens/supplier_screens.dart';
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
  const _Section(this.key, this.ar, this.icon, this.selectedIcon, this.pages, {this.wideOnly = false, this.hidden = false});
  /// Stable English name used by [Shell.go], whatever the interface language.
  final String key;
  final String ar;
  final IconData icon, selectedIcon;
  final List<(String, String, Widget Function(WarehouseStore, Shell))> pages;
  String get label => tx(key, ar);
  final bool wideOnly;

  /// Not in the navigation: opened as a page from elsewhere (Settings, home tiles).
  final bool hidden;
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
      ('Departments', 'الأقسام', (s, _) => DepartmentsScreen(store: s)),
    ]),
    _Section('Stock', 'المخزون', Icons.inventory_2_outlined, Icons.inventory_2, [
      ('Items', 'المواد', (s, _) => StockScreen(store: s)),
      ('Reorder', 'إعادة الطلب', (s, _) => ReorderScreen(store: s)),
      ('Expiry', 'الصلاحية', (s, _) => ExpiryScreen(store: s)),
      ('Count', 'الجرد', (s, _) => StockCountScreen(store: s)),
      ('Reports', 'التقارير', (s, _) => ReportsScreen(store: s)),
    ]),
    _Section('Purchases', 'المشتريات', Icons.shopping_cart_outlined, Icons.shopping_cart, [
      ('Purchases', 'قوائم الشراء', (s, _) => PurchasesScreen(store: s)),
      ('Payments', 'التسديد', (s, _) => SupplierPaymentsScreen(store: s)),
      ('Older bills', 'قوائم سابقة', (s, _) => PaymentsScreen(store: s)),
    ]),
    _Section('Month', 'الشهر', Icons.event_note_outlined, Icons.event_note, [
      ('Month end', 'نهاية الشهر', (s, _) => MonthScreen(store: s)),
    ]),
    _Section('Reserve', 'الاحتياط', Icons.warehouse_outlined, Icons.warehouse, [
      ('Reserve store', 'مخزن الاحتياط', (s, _) => ReserveScreen(store: s)),
      ('Count', 'الجرد', (s, _) => StockCountScreen(key: const ValueKey('reserve-count'), store: s, reserve: true)),
      ('Moves', 'النقل', (s, _) => TransfersScreen(store: s)),
    ], wideOnly: true),
    _Section('Equipment', 'المعدات', Icons.medical_services_outlined, Icons.medical_services, [
      ('Equipment', 'المعدات', (s, _) => EquipmentScreen(store: s)),
    ], wideOnly: true),
    _Section('Settings', 'الإعدادات', Icons.settings_outlined, Icons.settings, [
      ('Settings', 'الإعدادات', (s, sh) => SettingsScreen(store: s, shell: sh)),
    ], wideOnly: true),
    // Selling to clients: kept for older data, opened from Settings.
    _Section('Money', 'المبيعات والمصاريف', Icons.account_balance_wallet_outlined, Icons.account_balance_wallet, [
      ('Overview', 'نظرة عامة', (s, _) => ProfitScreen(store: s)),
      ('Invoices', 'الفواتير', (s, _) => InvoicesScreen(store: s)),
      ('Clients', 'الزبائن', (s, _) => ClientsScreen(store: s)),
      ('Expenses', 'المصاريف', (s, _) => ExpensesScreen(store: s)),
    ], hidden: true),
  ];

  /// Team members who are not owners only issue supplies to departments.
  static final _staffSections = <_Section>[
    _Section('Issue', 'الصرف', Icons.outbox_outlined, Icons.outbox, [
      ('Issues', 'وصولات الصرف', (s, _) => ReceiptsScreen(store: s)),
    ]),
    _Section('Account', 'الحساب', Icons.person_outline, Icons.person, [
      ('Account', 'الحساب', (s, _) => AccountScreen(store: s)),
    ]),
  ];

  @override
  void initState() {
    super.initState();
    widget.store.cloud?.onChanges = _showChanges;
  }

  @override
  void dispose() {
    if (widget.store.cloud?.onChanges == _showChanges) widget.store.cloud?.onChanges = null;
    super.dispose();
  }

  /// A notice at the bottom when someone else changed the shared store.
  void _showChanges(List<StoreChange> found) {
    if (!mounted || _staff) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.notifications_active_outlined, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(child: Text(changesNotice(found), maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: tx('View', 'عرض'), onPressed: () => openChanges(context, widget.store)),
      ));
  }

  bool get _staff => widget.store.cloud?.isStaff ?? false;
  List<_Section> get _secs => _staff ? _staffSections : _sections;

  @override
  void go(String section, [int page = 0]) {
    final i = _secs.indexWhere((s) => s.key == section);
    if (i < 0) return;
    // Phones have no tab for wide-only sections (Equipment, Settings), and hidden ones have none anywhere:
    // open them as a page instead.
    if (_secs[i].hidden || (_secs[i].wideOnly && MediaQuery.sizeOf(context).width < 700)) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => _SectionPage(section: _secs[i], page: page, store: widget.store, shell: this)));
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
        InsightTarget.expiry => go('Stock', 2),
        InsightTarget.money => go('Money'),
        InsightTarget.supplierBills => go('Purchases', 1),
        InsightTarget.settings => go('Settings'),
      };

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final phone = w < 700;
    final sections = _secs;
    if (_section >= sections.length || sections[_section].hidden) _section = 0;
    final visible = [for (final (i, s) in sections.indexed) if (!s.hidden && (!phone || !s.wideOnly)) i];
    final sec = sections[_section];
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
                        icon: Icon(sections[i].icon), selectedIcon: Icon(sections[i].selectedIcon), label: sections[i].label),
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
          selectedIndex: visible.indexOf(_section),
          onDestinationSelected: (i) => setState(() => _section = visible[i]),
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
                          child: Text(widget.store.companyName.isEmpty ? 'قسم التجهيز' : widget.store.companyName,
                              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                              overflow: TextOverflow.ellipsis)),
                    ]),
                  )
                : _Logo(color: scheme.primary),
          ),
          destinations: [
            for (final s in [for (final i in visible) sections[i]])
              NavigationRailDestination(icon: Icon(s.icon), selectedIcon: Icon(s.selectedIcon), label: Text(s.label)),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(child: body),
      ]),
    );
  }
}

/// A section opened as its own page, with its sub-page chips.
class _SectionPage extends StatefulWidget {
  const _SectionPage({required this.section, required this.page, required this.store, required this.shell});
  final _Section section;
  final int page;
  final WarehouseStore store;
  final Shell shell;

  @override
  State<_SectionPage> createState() => _SectionPageState();
}

class _SectionPageState extends State<_SectionPage> {
  late int _page = widget.page;

  @override
  Widget build(BuildContext context) => SubNav(
        labels: [for (final p in widget.section.pages) tx(p.$1, p.$2)],
        index: _page,
        onSelect: (i) => setState(() => _page = i),
        child: ListenableBuilder(
          listenable: widget.store,
          builder: (_, _) => KeyedSubtree(key: ValueKey(_page), child: widget.section.pages[_page].$3(widget.store, widget.shell)),
        ),
      );
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
