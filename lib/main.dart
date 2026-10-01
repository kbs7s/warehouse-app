import 'package:flutter/material.dart';
import 'package:sembast_web/sembast_web.dart';

import 'platform/files.dart';
import 'screens/equipment_screen.dart';
import 'screens/payments_screen.dart';
import 'screens/purchase_screens.dart';
import 'screens/receipt_screens.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/stock_screen.dart';
import 'screens/welcome_screen.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await databaseFactoryWeb.openDatabase('warehouse');
  final store = WarehouseStore(db);
  await store.load();
  requestPersistentStorage();
  runApp(WarehouseApp(store: store));
}

ThemeData buildTheme() {
  final base = ThemeData(
    colorSchemeSeed: const Color(0xFF00796B),
    useMaterial3: true,
    fontFamily: 'NotoSans',
    fontFamilyFallback: const ['NotoSansArabic'],
  );
  return base.copyWith(
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 10),
  );
}

class WarehouseApp extends StatelessWidget {
  const WarehouseApp({super.key, required this.store});
  final WarehouseStore store;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Warehouse',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: ListenableBuilder(
          listenable: store,
          builder: (_, _) => store.started ? HomeShell(store: store) : WelcomeScreen(store: store),
        ),
      );
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.store});
  final WarehouseStore store;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _dests = [
    (Icons.inventory_2_outlined, Icons.inventory_2, 'Stock'),
    (Icons.outbox_outlined, Icons.outbox, 'Issue'),
    (Icons.shopping_cart_outlined, Icons.shopping_cart, 'Purchases'),
    (Icons.bar_chart_outlined, Icons.bar_chart, 'Reports'),
    (Icons.payments_outlined, Icons.payments, 'Payments'),
    (Icons.medical_services_outlined, Icons.medical_services, 'Equipment'),
    (Icons.settings_outlined, Icons.settings, 'Backup'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      body: Row(children: [
        NavigationRail(
          extended: wide,
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          labelType: wide ? NavigationRailLabelType.none : NavigationRailLabelType.all,
          leading: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: wide
                ? const Text('قسم التجهيز', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))
                : const Icon(Icons.local_hospital_outlined, size: 32),
          ),
          destinations: [
            for (final d in _dests)
              NavigationRailDestination(icon: Icon(d.$1), selectedIcon: Icon(d.$2), label: Text(d.$3)),
          ],
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: ListenableBuilder(
            listenable: widget.store,
            builder: (_, _) => switch (_tab) {
              0 => StockScreen(store: widget.store),
              1 => ReceiptsScreen(store: widget.store),
              2 => PurchasesScreen(store: widget.store),
              3 => ReportsScreen(store: widget.store),
              4 => PaymentsScreen(store: widget.store),
              5 => EquipmentScreen(store: widget.store),
              _ => SettingsScreen(store: widget.store),
            },
          ),
        ),
      ]),
    );
  }
}
