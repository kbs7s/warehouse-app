import 'package:flutter/material.dart';

import 'insights.dart';
import 'l10n.dart';
import 'changes.dart';
import 'screens/archive_screens.dart';
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
import 'screens/labels_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/request_screens.dart';
import 'screens/reserve_screens.dart';
import 'screens/settings_screen.dart';
import 'screens/stock_screen.dart';
import 'screens/supplier_screens.dart';
import 'store.dart';
import 'theme.dart';
import 'ui.dart';

/// Sub-page chips shown under a section's title (e.g. Invoices | Clients).
class SubNav extends InheritedWidget {
  const SubNav({super.key, required this.labels, required this.index, required this.onSelect, required super.child});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onSelect;

  /// Switches to another page of the current section (no effect outside a section).
  static void select(BuildContext context, int index) =>
      context.getInheritedWidgetOfExactType<SubNav>()?.onSelect(index);

  /// The chips row for the current page's AppBar `bottom`, or null outside a section.
  static PreferredSizeWidget? bar(BuildContext context) {
    final nav = context.dependOnInheritedWidgetOfExactType<SubNav>();
    if (nav == null || nav.labels.length < 2) return null;
    // Tabs that sit on the bottom edge of the dark header; the open one joins the page below it.
    final page = Theme.of(context).scaffoldBackgroundColor;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return PreferredSize(
      preferredSize: const Size.fromHeight(50),
      child: Container(
        height: 50,
        width: double.infinity,
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
        ),
        // Chips paint on a canvas-coloured Material; clear it so closed tabs sit on the header.
        child: Theme(
          data: Theme.of(context).copyWith(canvasColor: Colors.transparent),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsetsDirectional.only(start: 12, end: 12, top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (i, l) in nav.labels.indexed)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 4),
                    child: ChoiceChip(
                      label: Text(l),
                      labelStyle: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: i == nav.index ? (dark ? const Color(0xFF5EEAD4) : const Color(0xFF134E4A)) : const Color(0xFFCCFBF1),
                      ),
                      selected: i == nav.index,
                      showCheckmark: false,
                      color: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? page : Colors.transparent),
                      side: BorderSide.none,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      onSelected: (_) => nav.onSelect(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool updateShouldNotify(SubNav old) => old.index != index || old.labels != labels;
}

class _Section {
  const _Section(this.key, this.ar, this.icon, this.selectedIcon, this.pages, {this.hidden = false});
  /// Stable English name used by [Shell.go], whatever the interface language.
  final String key;
  final String ar;
  final IconData icon, selectedIcon;
  final List<(String, String, Widget Function(WarehouseStore, Shell))> pages;
  String get label => tx(key, ar);

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
      ('Requests', 'طلبات الأقسام', (s, _) => RequestsScreen(store: s)),
      ('Departments', 'الأقسام', (s, _) => DepartmentsScreen(store: s)),
    ]),
    _Section('Stock', 'المخزون', Icons.inventory_2_outlined, Icons.inventory_2, [
      ('Items', 'المواد', (s, _) => StockScreen(store: s)),
      ('Reorder', 'إعادة الطلب', (s, _) => ReorderScreen(store: s)),
      ('Expiry', 'الصلاحية', (s, _) => ExpiryScreen(store: s)),
      ('Reports', 'التقارير', (s, _) => ReportsScreen(store: s)),
      ('Barcodes', 'الباركود', (s, _) => LabelsScreen(store: s)),
    ]),
    // Stock counts of both stores, each on its own page.
    _Section('Count', 'الجرد', Icons.fact_check_outlined, Icons.fact_check, [
      ('Main store', 'المخزن الأساسي', (s, _) => StockCountScreen(store: s)),
      ('Reserve store', 'مخزن الاحتياط', (s, _) => StockCountScreen(key: const ValueKey('reserve-count'), store: s, reserve: true)),
    ]),
    _Section('Purchases', 'المشتريات', Icons.shopping_cart_outlined, Icons.shopping_cart, [
      ('Purchases', 'قوائم الشراء', (s, _) => PurchasesScreen(store: s)),
      ('Payments', 'التسديد', (s, _) => SupplierPaymentsScreen(store: s)),
      ('Older bills', 'قوائم سابقة', (s, _) => PaymentsScreen(store: s)),
    ]),
    _Section('Month', 'الشهر', Icons.event_note_outlined, Icons.event_note, [
      ('Month end', 'نهاية الشهر', (s, _) => MonthScreen(store: s)),
      ('Archive', 'الأرشيف', (s, _) => MonthArchiveScreen(store: s)),
    ]),
    _Section('Reserve', 'الاحتياط', Icons.warehouse_outlined, Icons.warehouse, [
      ('Reserve store', 'مخزن الاحتياط', (s, _) => ReserveScreen(store: s)),
      ('Moves', 'النقل', (s, _) => TransfersScreen(store: s)),
    ]),
    _Section('Equipment', 'المعدات', Icons.medical_services_outlined, Icons.medical_services, [
      ('Equipment', 'المعدات', (s, _) => EquipmentScreen(store: s)),
    ]),
    _Section('Settings', 'الإعدادات', Icons.settings_outlined, Icons.settings, [
      ('Settings', 'الإعدادات', (s, sh) => SettingsScreen(store: s, shell: sh)),
    ]),
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
      ('Requests', 'طلبات الأقسام', (s, _) => RequestsScreen(store: s)),
    ]),
    _Section('Account', 'الحساب', Icons.person_outline, Icons.person, [
      ('Account', 'الحساب', (s, _) => AccountScreen(store: s)),
    ]),
  ];

  /// A department login only sends requests to the store.
  static final _deptSections = <_Section>[
    _Section('Requests', 'الطلبات', Icons.assignment_outlined, Icons.assignment, [
      ('Requests', 'طلباتي', (s, _) => RequestsScreen(store: s)),
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
  List<_Section> get _secs => (widget.store.cloud?.isDept ?? false) ? _deptSections : _staff ? _staffSections : _sections;

  @override
  void go(String section, [int page = 0]) {
    final i = _secs.indexWhere((s) => s.key == section);
    if (i < 0) return;
    // Hidden sections have no place in the side panel: open them as a page instead.
    if (_secs[i].hidden) {
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

  final _scaffold = GlobalKey<ScaffoldState>();

  /// Wide screens: whether the side panel shows names (open) or only icons. Null until the user toggles it.
  bool? _panelOpen;

  void _select(int i) {
    setState(() => _section = i);
    // On a phone the panel slides over the page: close it once a section is picked.
    if (_scaffold.currentState?.isDrawerOpen ?? false) Navigator.of(context).pop();
  }

  Future<void> _signOut() async {
    final c = widget.store.cloud;
    if (c == null) return;
    if (_scaffold.currentState?.isDrawerOpen ?? false) Navigator.of(context).pop();
    if (await confirm(
        context,
        tx('Sign out?', 'تسجيل الخروج؟'),
        tx('The shared data is removed from this device. It stays online for the rest of the team.',
            'ستُحذف البيانات المشتركة من هذا الجهاز، وتبقى أونلاين لبقية الفريق.'),
        action: tx('Sign out', 'تسجيل الخروج'))) {
      await c.syncNow();
      await c.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final phone = w < 700;
    final sections = _secs;
    if (_section >= sections.length || sections[_section].hidden) _section = 0;
    final visible = [for (final (i, s) in sections.indexed) if (!s.hidden) i];
    final sec = sections[_section];
    final pageIdx = _page[_section] ?? 0;
    final open = _panelOpen ?? w >= 1100;
    final body = MenuScope(
      onMenu: phone ? () => _scaffold.currentState?.openDrawer() : () => setState(() => _panelOpen = !open),
      child: SubNav(
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
      ),
    );

    // Settings sits apart at the bottom of the panel, with Sign out.
    final settings = sections.indexWhere((s) => s.key == 'Settings');
    final panel = _SidePanel(
      title: widget.store.companyName.isEmpty ? 'قسم التجهيز' : widget.store.companyName,
      entries: [for (final i in visible) if (i != settings) (i, sections[i])],
      bottom: [if (settings >= 0) (settings, sections[settings])],
      selected: _section,
      open: phone || open,
      onSelect: _select,
      onSignOut: (widget.store.cloud?.signedIn ?? false) ? _signOut : null,
    );

    if (phone) {
      return Scaffold(
        key: _scaffold,
        drawer: Drawer(
          width: 300,
          backgroundColor: Colors.transparent,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadiusDirectional.horizontal(end: Radius.circular(24))),
          clipBehavior: Clip.antiAlias,
          child: panel,
        ),
        body: body,
      );
    }
    return Scaffold(
      key: _scaffold,
      body: Row(children: [panel, Expanded(child: body)]),
    );
  }
}

/// The dark side panel listing the sections: the open one is a light rounded pill.
/// Open it shows icons with names; closed (wide screens only) a narrow strip of icons with short names.
class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.title,
    required this.entries,
    required this.bottom,
    required this.selected,
    required this.open,
    required this.onSelect,
    required this.onSignOut,
  });
  final String title;
  final List<(int, _Section)> entries, bottom;
  final int selected;
  final bool open;
  final ValueChanged<int> onSelect;
  final VoidCallback? onSignOut;

  static const _openWidth = 260.0, _closedWidth = 92.0;

  @override
  Widget build(BuildContext context) {
    final dir = Directionality.of(context);
    final width = open ? _openWidth : _closedWidth;
    Widget item(int i, _Section s) => _PanelItem(
        icon: i == selected ? s.selectedIcon : s.icon, label: s.label, selected: i == selected, open: open, onTap: () => onSelect(i));
    final line = Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 16), color: const Color(0x1FFFFFFF));
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      width: width,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: AppColors.header,
        ),
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: AlignmentDirectional.topStart.resolve(dir),
          minWidth: width,
          maxWidth: width,
          child: SafeArea(
            right: dir == TextDirection.ltr,
            left: dir == TextDirection.rtl,
            child: Column(children: [
              Padding(
                padding: EdgeInsets.fromLTRB(open ? 18 : 0, 18, open ? 18 : 0, 16),
                child: open
                    ? Row(children: [
                        const _Logo(),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text(title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, height: 1.3)),
                            Text(tx('Store management', 'إدارة المخزن'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xCCFFFFFF), fontSize: 13, height: 1.3)),
                          ]),
                        ),
                      ])
                    : const Center(child: _Logo()),
              ),
              line,
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  children: [for (final (i, s) in entries) item(i, s)],
                ),
              ),
              if (bottom.isNotEmpty || onSignOut != null) ...[
                line,
                const SizedBox(height: 8),
                for (final (i, s) in bottom) item(i, s),
                if (onSignOut != null)
                  _PanelItem(icon: Icons.logout, label: tx('Sign out', 'تسجيل الخروج'), selected: false, open: open, onTap: onSignOut!),
                const SizedBox(height: 12),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _PanelItem extends StatelessWidget {
  const _PanelItem({required this.icon, required this.label, required this.selected, required this.open, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected, open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final dark = t.brightness == Brightness.dark;
    // The open section's pill takes the page colour, so it reads as joined to the page.
    final pill = t.scaffoldBackgroundColor;
    final fg = selected ? (dark ? const Color(0xFF5EEAD4) : const Color(0xFF134E4A)) : const Color(0xF2FFFFFF);
    final iconColor = selected ? (dark ? const Color(0xFF5EEAD4) : AppColors.brand) : const Color(0xE6FFFFFF);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(open ? 16 : 14));
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: open ? 12 : 10, vertical: 2),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? pill : Colors.transparent,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: onTap,
            hoverColor: const Color(0x14FFFFFF),
            splashColor: const Color(0x22FFFFFF),
            child: open
                ? SizedBox(
                    height: 52,
                    child: Row(children: [
                      const SizedBox(width: 16),
                      Icon(icon, color: iconColor, size: 24),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: fg, fontSize: 16, fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
                      ),
                    ]),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(children: [
                      Icon(icon, color: iconColor, size: 24),
                      const SizedBox(height: 2),
                      Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: fg, fontSize: 12, fontWeight: selected ? FontWeight.w800 : FontWeight.w600)),
                    ]),
                  ),
          ),
        ),
      ),
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
  const _Logo();
  @override
  Widget build(BuildContext context) => Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: AppColors.brand,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x4D5EEAD4)),
        ),
        child: const Icon(Icons.inventory_2, color: Color(0xFFCCFBF1), size: 24),
      );
}
