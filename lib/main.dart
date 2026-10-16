import 'package:flutter/material.dart';
import 'package:sembast_web/sembast_web.dart';

import 'platform/files.dart';
import 'screens/welcome_screen.dart';
import 'shell.dart';
import 'store.dart';
import 'theme.dart';

export 'shell.dart' show HomeShell;
export 'theme.dart' show buildTheme;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 'business' (not v1's 'warehouse') so the new version never changes the old app's data.
  // On first start, the old app's data is copied over from 'warehouse'.
  final db = await databaseFactoryWeb.openDatabase('business');
  final store = WarehouseStore(db);
  final legacy = await databaseFactoryWeb.openDatabase('warehouse');
  await store.load(legacy: legacy);
  await legacy.close();
  requestPersistentStorage();
  runApp(BusinessApp(store: store));
}

class BusinessApp extends StatelessWidget {
  const BusinessApp({super.key, required this.store});
  final WarehouseStore store;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Business',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: ListenableBuilder(
          listenable: store,
          builder: (_, _) => store.started ? HomeShell(store: store) : WelcomeScreen(store: store),
        ),
      );
}
