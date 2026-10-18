import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sembast/sembast.dart';

import 'cloud.dart';
import 'merge.dart';
import 'store.dart';

enum SyncState { off, synced, working, offline, error }

/// Keeps this device's data and the shared online copy the same.
///
/// The device always works from its own saved copy, so the app keeps working without internet.
/// A few seconds after each change, and every half minute, it compares with the online copy:
/// changes from either side are taken over, and if both sides changed, the two are merged
/// (see mergeData) using the last copy both agreed on ("base"), which is kept on the device.
class CloudSync extends ChangeNotifier {
  CloudSync(this.store, this._db, {http.Client? httpClient, CloudConfig? config, this.pollEvery = const Duration(seconds: 30)})
      : _http = httpClient,
        config = config ?? CloudConfig.builtIn {
    store.onLocalSave = _localChanged;
    store.cloud = this;
  }

  final WarehouseStore store;
  final Database? _db;
  final http.Client? _http;
  final Duration pollEvery;
  static final _sessionRecord = StoreRef<String, String>.main().record('cloud');
  static final _baseRecord = StoreRef<String, String>.main().record('cloudBase');

  CloudConfig config;
  CloudClient? _client;
  Member? member;
  SyncState state = SyncState.off;
  String? error;
  DateTime? lastSync;
  String? lastBy; // who saved the online copy last

  String? _baseTime;
  String? _base; // canonical JSON of the last copy this device and the online copy agreed on
  Timer? _poll, _debounce;
  bool _applying = false;
  Future<void>? _running;
  bool _again = false;

  bool get signedIn => _client?.user != null;
  String? get email => _client?.user?.email;
  bool get isOwner => member?.isOwner ?? false;
  CloudClient? get client => _client;

  /// Picks up a saved sign-in on this device.
  Future<void> load() async {
    final saved = _db == null ? null : await _sessionRecord.get(_db);
    if (saved == null) return;
    final j = jsonDecode(saved) as Map<String, dynamic>;
    final c = CloudConfig.fromJson((j['config'] as Map).cast<String, dynamic>());
    if (c.isSet) config = c;
    final base = _db == null ? null : await _baseRecord.get(_db);
    if (base != null) {
      final b = jsonDecode(base) as Map<String, dynamic>;
      _baseTime = b['updateTime'] as String?;
      _base = b['data'] as String?;
    }
    final mail = j['email'] as String?, token = j['refreshToken'] as String?;
    if (mail == null || token == null) return;
    _client = CloudClient(config, client: _http)
      ..user = CloudUser(email: mail, uid: '', idToken: '', refreshToken: token, expires: DateTime(2000));
    if (j['role'] != null) member = Member(email: mail, role: j['role'] as String, name: (j['name'] as String?) ?? '');
    state = SyncState.working;
    _startPolling();
    unawaited(syncNow());
  }

  /// Signs in to the shared store and takes over its data on this device.
  Future<void> signIn(CloudConfig cfg, String email, String password) async {
    final c = CloudClient(cfg, client: _http);
    await c.signIn(email, password);
    final me = await c.me();
    if (me == null) throw CloudError('PERMISSION_DENIED');
    final remote = await c.fetch();
    config = cfg;
    _client = c;
    member = me;
    if (remote == null) {
      // The owner signed up but nothing was uploaded yet: this device's data becomes the shared copy.
      if (!store.started) _apply(_emptyData);
      await _setBase(await c.save(_snapshot(), expected: null), _snapshot());
    } else {
      _apply(remote.data);
      await _setBase(remote.updateTime, _snapshot());
      lastBy = remote.updatedBy;
    }
    await _saveSession();
    _done();
    _startPolling();
    store.refresh();
  }

  /// First-time setup: creates the owner's account and uploads this device's data as the shared copy.
  Future<void> createStore(CloudConfig cfg, String email, String password, {String name = ''}) async {
    final c = CloudClient(cfg, client: _http);
    try {
      await c.signUp(email, password);
    } on CloudError catch (e) {
      if (e.code != 'EMAIL_EXISTS') rethrow;
      await c.signIn(email, password);
    }
    final me = Member(email: c.user!.email, name: name, role: 'owner');
    try {
      await c.setMember(me);
    } on CloudError catch (e) {
      if (e.code == 'PERMISSION_DENIED') {
        throw CloudError('The shared store is already set up. Ask its owner to add you, then sign in.');
      }
      rethrow;
    }
    config = cfg;
    _client = c;
    member = me;
    if (!store.started) _apply(_emptyData);
    try {
      await _setBase(await c.save(_snapshot(), expected: null), _snapshot());
    } on CloudConflict {
      // Data was already there (setup was started before): take it over instead.
      final remote = (await c.fetch())!;
      _apply(remote.data);
      await _setBase(remote.updateTime, _snapshot());
    }
    await _saveSession();
    _done();
    _startPolling();
    store.refresh();
  }

  /// Signs out and removes the shared data from this device.
  Future<void> signOut() async {
    _poll?.cancel();
    _debounce?.cancel();
    _client = null;
    member = null;
    _base = null;
    _baseTime = null;
    state = SyncState.off;
    if (_db != null) {
      await _sessionRecord.delete(_db);
      await _baseRecord.delete(_db);
    }
    await store.eraseAll();
    notifyListeners();
  }

  /// Compares with the online copy now and brings both up to date.
  Future<void> syncNow() async {
    if (!signedIn) return;
    if (_running != null) {
      _again = true;
      return _running;
    }
    _running = _sync();
    try {
      await _running;
    } finally {
      _running = null;
    }
    if (_again) {
      _again = false;
      await syncNow();
    }
  }

  Future<void> _sync() async {
    final c = _client!;
    state = SyncState.working;
    notifyListeners();
    try {
      if (member == null || member!.email != c.user!.email) {
        member = await c.me();
        if (member == null) throw CloudError('PERMISSION_DENIED');
        await _saveSession();
      }
      for (var attempt = 0; attempt < 5; attempt++) {
        final local = _snapshot();
        final remote = await c.fetch();
        try {
          if (!store.started) {
            // Nothing on this device (it was erased): never send that over the shared copy.
            if (remote != null) {
              _apply(remote.data);
              await _setBase(remote.updateTime, _snapshot());
            }
          } else if (remote == null) {
            await _setBase(await c.save(local, expected: null), local);
          } else if (remote.updateTime == _baseTime) {
            if (_canon(local) != _base) await _setBase(await c.save(local, expected: remote.updateTime), local);
          } else {
            lastBy = remote.updatedBy;
            final changedHere = _base == null || _canon(local) != _base;
            if (!changedHere) {
              _apply(remote.data);
              await _setBase(remote.updateTime, _snapshot());
            } else {
              final base = _base == null ? remote.data : jsonDecode(_base!) as Map<String, dynamic>;
              final merged = mergeData(base, local, remote.data);
              _apply(merged);
              final now = _snapshot();
              await _setBase(await c.save(now, expected: remote.updateTime), now);
            }
          }
          _done();
          return;
        } on CloudConflict {
          continue; // someone saved in between: read again and merge
        }
      }
      throw CloudError('Could not save: the online copy keeps changing. Try again.');
    } on CloudError catch (e) {
      error = e.message;
      state = e.code == 'OFFLINE' ? SyncState.offline : SyncState.error;
      notifyListeners();
    }
  }

  void _done() {
    state = SyncState.synced;
    error = null;
    lastSync = DateTime.now();
    notifyListeners();
    unawaited(_saveSession()); // the sign-in token may have been renewed
  }

  void _localChanged() {
    if (_applying || !signedIn) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), syncNow);
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(pollEvery, (_) => syncNow());
  }

  void _apply(Map<String, dynamic> data) {
    _applying = true;
    try {
      store.applyJson(data);
    } finally {
      _applying = false;
    }
  }

  static const _emptyData = {'format': 'warehouse-backup', 'version': 2, 'source': 'Shared online store'};

  /// This device's data without the fields that change on every save.
  Map<String, dynamic> _snapshot() => store.toJson()..remove('savedAt');

  static String _canon(Map<String, dynamic> j) => jsonEncode({...j}..remove('savedAt'));

  Future<void> _setBase(String updateTime, Map<String, dynamic> data) async {
    _baseTime = updateTime;
    _base = _canon(data);
    if (_db != null) await _baseRecord.put(_db, jsonEncode({'updateTime': _baseTime, 'data': _base}));
  }

  Future<void> _saveSession() async {
    final u = _client?.user;
    if (_db == null || u == null) return;
    await _sessionRecord.put(
        _db,
        jsonEncode({
          'config': config.toJson(),
          'email': u.email,
          'refreshToken': u.refreshToken,
          if (member != null) 'role': member!.role,
          if (member != null) 'name': member!.name,
        }));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _debounce?.cancel();
    super.dispose();
  }
}
