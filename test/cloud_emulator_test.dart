// Runs against the Firebase emulators (auth + firestore) with the real rules:
//   cd firebase && npx firebase-tools emulators:start --project demo-store --only auth,firestore
//   FIREBASE_EMULATOR=localhost flutter test test/cloud_emulator_test.dart
// Skipped when FIREBASE_EMULATOR is not set.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:warehouse_app/cloud.dart';
import 'package:warehouse_app/models.dart';
import 'package:warehouse_app/store.dart';
import 'package:warehouse_app/sync.dart';

void main() {
  final host = Platform.environment['FIREBASE_EMULATOR'];
  final cfg = CloudConfig(projectId: 'demo-store', apiKey: 'fake-key', emulatorHost: host);
  const hour = Duration(hours: 1);

  setUp(() async {
    if (host == null) return;
    await http.delete(Uri.parse('http://$host:8080/emulator/v1/projects/demo-store/databases/(default)/documents'));
    await http.delete(Uri.parse('http://$host:9099/emulator/v1/projects/demo-store/accounts'));
  });

  Map<String, dynamic> data() => {
        'format': 'warehouse-backup',
        'items': [
          {'id': 'P001', 'name': 'Gloves', 'unit': 'box', 'openingQty': 10},
          {'id': 'P002', 'name': 'Masks', 'unit': 'box', 'openingQty': 5},
        ],
        'departments': ['ICU'],
      };

  test('owner sets up, adds staff, both edit at the same time and nothing is lost', () async {
    final ownerStore = WarehouseStore(null)..applyJson(data());
    final owner = CloudSync(ownerStore, null, pollEvery: hour);
    await owner.createStore(cfg, 'owner@example.com', 'secret1', name: 'Karar');
    expect(owner.isOwner, isTrue);

    // A second sign-up as owner is refused once the store exists.
    final intruder = CloudSync(WarehouseStore(null), null, pollEvery: hour);
    await expectLater(intruder.createStore(cfg, 'x@example.com', 'secret1'), throwsA(isA<CloudError>()));
    await expectLater(intruder.signIn(cfg, 'x@example.com', 'secret1'), throwsA(isA<CloudError>()));
    expect(intruder.store.items, isEmpty);

    // Owner adds a staff member.
    await owner.client!.signUp('staff@example.com', 'secret2', keepCurrent: true);
    await owner.client!.setMember(Member(email: 'staff@example.com', name: 'Ali'));
    expect((await owner.client!.members()).map((m) => m.email), ['owner@example.com', 'staff@example.com']);

    final staffStore = WarehouseStore(null);
    final staff = CloudSync(staffStore, null, pollEvery: hour);
    await staff.signIn(cfg, 'staff@example.com', 'secret2');
    expect(staffStore.items.map((i) => i.id), ['P001', 'P002']);
    expect(staff.isOwner, isFalse);

    // Staff cannot change the team.
    await expectLater(staff.client!.setMember(Member(email: 'staff@example.com', role: 'owner')), throwsA(isA<CloudError>()));

    // Both issue supplies before seeing each other's change: both get receipt no 1.
    ownerStore.saveReceipt(Receipt(no: 1, date: '2026-10-18', department: 'ICU', lines: [ReceiptLine(itemId: 'P001', qty: 2)]));
    staffStore.saveReceipt(Receipt(no: 1, date: '2026-10-18', department: 'NICU', lines: [ReceiptLine(itemId: 'P002', qty: 1)]));
    await owner.syncNow();
    await staff.syncNow();
    await owner.syncNow();
    expect(owner.error, isNull);
    expect(owner.state, SyncState.synced);
    expect(staff.state, SyncState.synced);
    for (final s in [ownerStore, staffStore]) {
      expect(s.receipts.map((r) => '${r.no}:${r.department}').toList()..sort(), ['1:ICU', '2:NICU']);
      expect(s.stock('P001').qty, 8);
      expect(s.stock('P002').qty, 4);
    }

    // An owner's edit reaches the staff device on its next sync.
    ownerStore.saveItem(ownerStore.item('P002')!..minLevel = 3);
    await owner.syncNow();
    await staff.syncNow();
    expect(staffStore.item('P002')!.minLevel, 3);

    // Staff may only issue: other changes on their device are undone and never reach the owner.
    staffStore.saveItem(staffStore.item('P001')!..minLevel = 99);
    staffStore.saveReceipt(Receipt(no: 3, date: '2026-10-19', department: 'ER', lines: [ReceiptLine(itemId: 'P001', qty: 1)]));
    await staff.syncNow();
    await owner.syncNow();
    expect(staffStore.item('P001')!.minLevel, 0);
    expect(ownerStore.item('P001')!.minLevel, 0);
    expect(ownerStore.receipts.map((r) => r.department), contains('ER'));

    // The owner was told about what the staff member did, credited to them by name.
    final told = [for (final c in owner.changes) '${c.by}: ${c.en}'];
    expect(told, contains('Ali: Issue #3 to ER · 1 item'));
    expect(told.where((t) => t.contains('Gloves')), isEmpty); // the undone item edit never arrived
    expect(owner.unread, greaterThan(0));
    await owner.markRead();
    expect(owner.unread, 0);

    // Removing a member locks them out.
    await owner.client!.removeMember('staff@example.com');
    staff.member = null;
    await staff.syncNow();
    expect(staff.state, SyncState.error);

    await staff.signOut();
    expect(staffStore.started, isFalse);
  }, skip: host == null ? 'Set FIREBASE_EMULATOR to run against the Firebase emulators' : null);
}
