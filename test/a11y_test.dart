import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:warehouse_app/main.dart';
import 'package:warehouse_app/store.dart';

// Accessibility checks on the main pages, in day and night mode, on a phone: every button is
// big enough to tap and has a name a screen reader can say, and text is readable on its background.
void main() {
  late WarehouseStore store;
  setUp(() {
    store = WarehouseStore(null)
      ..applyJson(jsonDecode(File('seed/app_seed.json').readAsStringSync()) as Map<String, dynamic>,
          save: false);
  });

  for (final dark in [false, true]) {
    for (final section in ['Home', 'Issue', 'Stock', 'Month', 'Purchases']) {
      testWidgets('$section page meets tap size, label and contrast guidelines (${dark ? 'night' : 'day'})', (t) async {
        t.view.physicalSize = const Size(1170, 2532);
        t.view.devicePixelRatio = 3;
        addTearDown(t.view.reset);
        final handle = t.ensureSemantics();
        await t.pumpWidget(MaterialApp(
            theme: buildTheme(dark ? Brightness.dark : Brightness.light), home: HomeShell(store: store)));
        if (section != 'Home') {
          await t.tap(find.text(section).last);
        }
        await t.pumpAndSettle();
        await expectLater(t, meetsGuideline(androidTapTargetGuideline));
        await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(t, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }
  }
}
