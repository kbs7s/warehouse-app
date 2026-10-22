import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:sembast_web/sembast_web.dart';

import 'l10n.dart';
import 'platform/files.dart';
import 'screens/welcome_screen.dart';
import 'shell.dart';
import 'store.dart';
import 'sync.dart';
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
  await CloudSync(store, db).load();
  requestPersistentStorage();
  runApp(BusinessApp(store: store));
}

class BusinessApp extends StatelessWidget {
  const BusinessApp({super.key, required this.store});
  final WarehouseStore store;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: store,
        builder: (_, _) {
          isAr = store.lang == 'ar';
          appAccent = accentChoices[store.accent.clamp(0, accentChoices.length - 1)].$3;
          return MaterialApp(
            title: 'Business',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light, appAccent),
            darkTheme: buildTheme(Brightness.dark, appAccent),
            themeMode: switch (store.themeMode) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system },
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(store.textSize)),
              child: child!,
            ),
            // Arabic turns the whole layout right-to-left; Western digits are kept in both languages.
            locale: Locale(store.lang),
            supportedLocales: const [Locale('en'), Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: KeyedSubtree(
              key: ValueKey(store.lang),
              child: store.started ? HomeShell(store: store) : WelcomeScreen(store: store),
            ),
          );
        },
      );
}
