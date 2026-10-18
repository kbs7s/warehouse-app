import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

/// The online store: a free Firebase project (Spark plan) used through its REST APIs, so the app
/// needs no extra SDK and keeps working offline. Sign-in is Firebase email and password; the data
/// is one Firestore document holding the same JSON as a backup file, gzip-compressed.
///
/// Who may read and write is decided by the Firestore rules in firebase/firestore.rules: only
/// people listed in the `members` collection, and only an owner can change that list.
class CloudConfig {
  const CloudConfig({required this.projectId, required this.apiKey, this.emulatorHost});
  final String projectId;
  final String apiKey;

  /// 'localhost' to talk to the Firebase emulators instead (tests only).
  final String? emulatorHost;

  bool get isSet => projectId.isNotEmpty && apiKey.isNotEmpty;

  /// The shared store's Firebase project (hospital-store-a4ce1). A build can point elsewhere with
  /// --dart-define FIREBASE_PROJECT / FIREBASE_API_KEY.
  static const builtIn = CloudConfig(
    projectId: String.fromEnvironment('FIREBASE_PROJECT', defaultValue: 'hospital-store-a4ce1'),
    // A Firebase web key only names the project; the Firestore rules decide who can read the data.
    apiKey: String.fromEnvironment('FIREBASE_API_KEY', defaultValue: 'AIzaSyAsPVtmHL5pmRUL_ksZdyayZLz_jEs4_5A'),
    emulatorHost: bool.hasEnvironment('FIREBASE_EMULATOR') ? String.fromEnvironment('FIREBASE_EMULATOR') : null,
  );

  String get _authBase => emulatorHost == null
      ? 'https://identitytoolkit.googleapis.com/v1'
      : 'http://$emulatorHost:9099/identitytoolkit.googleapis.com/v1';
  String get _tokenUrl => emulatorHost == null
      ? 'https://securetoken.googleapis.com/v1/token'
      : 'http://$emulatorHost:9099/securetoken.googleapis.com/v1/token';
  String get _docsName => 'projects/$projectId/databases/(default)/documents';
  String get _docsBase => '${emulatorHost == null ? 'https://firestore.googleapis.com' : 'http://$emulatorHost:8080'}/v1/$_docsName';

  Map<String, dynamic> toJson() => {'projectId': projectId, 'apiKey': apiKey, if (emulatorHost != null) 'emulatorHost': emulatorHost};
  factory CloudConfig.fromJson(Map<String, dynamic> j) => CloudConfig(
      projectId: (j['projectId'] as String?) ?? '', apiKey: (j['apiKey'] as String?) ?? '', emulatorHost: j['emulatorHost'] as String?);
}

class CloudUser {
  CloudUser({required this.email, required this.uid, required this.idToken, required this.refreshToken, required this.expires});
  final String email, uid;
  String idToken, refreshToken;
  DateTime expires;

  Map<String, dynamic> toJson() => {'email': email, 'uid': uid, 'refreshToken': refreshToken};
}

class Member {
  Member({required this.email, this.name = '', this.role = 'staff'});
  final String email;
  final String name;
  final String role; // 'owner' or 'staff'
  bool get isOwner => role == 'owner';
}

/// The shared data as last saved online.
class RemoteData {
  RemoteData({required this.data, required this.updateTime, this.updatedBy});
  final Map<String, dynamic> data;
  final String updateTime; // Firestore's version stamp, sent back to detect conflicting saves
  final String? updatedBy;
}

/// Thrown when someone else saved since we last read; the caller merges and tries again.
class CloudConflict implements Exception {}

class CloudError implements Exception {
  CloudError(this.code, [this.status]);
  final String code;
  final int? status;

  /// A short, readable reason for the person using the app.
  String get message => switch (code) {
        'EMAIL_NOT_FOUND' || 'INVALID_PASSWORD' || 'INVALID_LOGIN_CREDENTIALS' => 'Wrong email or password.',
        'EMAIL_EXISTS' => 'That email already has an account.',
        'INVALID_EMAIL' => 'That email address is not valid.',
        'USER_DISABLED' => 'This account is turned off.',
        'TOO_MANY_ATTEMPTS_TRY_LATER' => 'Too many tries. Wait a few minutes.',
        'PERMISSION_DENIED' => 'This account is not on the team. Ask the owner to add it.',
        'API_KEY_INVALID' || 'INVALID_API_KEY' => 'The Web API key is not right.',
        'OFFLINE' => 'No internet connection.',
        _ when code.startsWith('WEAK_PASSWORD') => 'Password must be at least 6 characters.',
        _ => code,
      };

  @override
  String toString() => message;
}

class CloudClient {
  CloudClient(this.config, {http.Client? client}) : _http = client ?? http.Client();
  final CloudConfig config;
  final http.Client _http;
  CloudUser? user;

  static const storeDoc = 'stores/main';

  // ---- Sign-in ----

  Future<CloudUser> signIn(String email, String password) async {
    final j = await _authPost('accounts:signInWithPassword', {'email': email.trim(), 'password': password, 'returnSecureToken': true});
    return user = _userFrom(j);
  }

  /// Creates a sign-in account. With [keepCurrent] the current user stays signed in (adding a
  /// team member); otherwise the new account is signed in (setting up the store).
  Future<CloudUser> signUp(String email, String password, {bool keepCurrent = false}) async {
    final j = await _authPost('accounts:signUp', {'email': email.trim(), 'password': password, 'returnSecureToken': true});
    final u = _userFrom(j);
    if (!keepCurrent) user = u;
    return u;
  }

  Future<void> sendPasswordReset(String email) =>
      _authPost('accounts:sendOobCode', {'requestType': 'PASSWORD_RESET', 'email': email.trim()});

  /// Signs in again with a saved refresh token (keeps a device signed in between visits).
  Future<CloudUser> resume(String email, String refreshToken) async {
    user = CloudUser(email: email, uid: '', idToken: '', refreshToken: refreshToken, expires: DateTime(2000));
    await _token();
    return user!;
  }

  CloudUser _userFrom(Map<String, dynamic> j) => CloudUser(
        email: ((j['email'] as String?) ?? '').toLowerCase(),
        uid: (j['localId'] as String?) ?? '',
        idToken: j['idToken'] as String,
        refreshToken: j['refreshToken'] as String,
        expires: DateTime.now().add(Duration(seconds: int.tryParse('${j['expiresIn']}') ?? 3600) - const Duration(minutes: 5)),
      );

  Future<String> _token() async {
    final u = user;
    if (u == null) throw CloudError('Not signed in');
    if (DateTime.now().isBefore(u.expires)) return u.idToken;
    final res = await _send(() => _http.post(Uri.parse('${config._tokenUrl}?key=${config.apiKey}'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'grant_type=refresh_token&refresh_token=${Uri.encodeQueryComponent(u.refreshToken)}'));
    final j = _decode(res);
    if (res.statusCode != 200) throw _error(j, res.statusCode);
    u.idToken = j['id_token'] as String;
    u.refreshToken = j['refresh_token'] as String;
    u.expires = DateTime.now().add(Duration(seconds: int.tryParse('${j['expires_in']}') ?? 3600) - const Duration(minutes: 5));
    return u.idToken;
  }

  Future<Map<String, dynamic>> _authPost(String method, Map<String, dynamic> body) async {
    final res = await _send(() => _http.post(Uri.parse('${config._authBase}/$method?key=${config.apiKey}'),
        headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)));
    final j = _decode(res);
    if (res.statusCode != 200) throw _error(j, res.statusCode);
    return j;
  }

  // ---- Documents ----

  Future<Map<String, String>> _headers() async =>
      {'Authorization': 'Bearer ${await _token()}', 'Content-Type': 'application/json'};

  /// The shared data, or null when nobody has uploaded any yet.
  Future<RemoteData?> fetch() async {
    final res = await _send(() async => _http.get(Uri.parse('${config._docsBase}/$storeDoc'), headers: await _headers()));
    if (res.statusCode == 404) return null;
    final j = _decode(res);
    if (res.statusCode != 200) throw _error(j, res.statusCode);
    final f = (j['fields'] as Map<String, dynamic>?) ?? {};
    final bytes = base64Decode((f['data'] as Map?)?['bytesValue'] as String? ?? '');
    return RemoteData(
      data: jsonDecode(utf8.decode(const GZipDecoder().decodeBytes(bytes))) as Map<String, dynamic>,
      updateTime: j['updateTime'] as String,
      updatedBy: (f['updatedBy'] as Map?)?['stringValue'] as String?,
    );
  }

  /// Saves the shared data if it is still at [expected] (null: only if there is none yet).
  /// Returns the new version stamp; throws [CloudConflict] if someone else saved first.
  Future<String> save(Map<String, dynamic> data, {required String? expected}) async {
    final packed = base64Encode(const GZipEncoder().encodeBytes(utf8.encode(jsonEncode(data))));
    // A commit with a precondition: it only goes through if nobody saved since [expected].
    final res = await _send(() async => _http.post(Uri.parse('${config._docsBase}:commit'),
        headers: await _headers(),
        body: jsonEncode({
          'writes': [
            {
              'update': {
                'name': '${config._docsName}/$storeDoc',
                'fields': {
                  'data': {'bytesValue': packed},
                  'updatedBy': {'stringValue': user?.email ?? ''},
                  'updatedAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
                },
              },
              'currentDocument': expected == null ? {'exists': false} : {'updateTime': expected},
            }
          ]
        })));
    final j = _decode(res);
    final status = (j['error'] as Map?)?['status'];
    if (res.statusCode == 409 || status == 'FAILED_PRECONDITION' || status == 'ALREADY_EXISTS' || (status == 'NOT_FOUND' && expected != null)) {
      throw CloudConflict();
    }
    if (res.statusCode != 200) throw _error(j, res.statusCode);
    return ((j['writeResults'] as List).first as Map)['updateTime'] as String;
  }

  Future<List<Member>> members() async {
    final res = await _send(() async => _http.get(Uri.parse('${config._docsBase}/members?pageSize=300'), headers: await _headers()));
    final j = _decode(res);
    if (res.statusCode != 200) throw _error(j, res.statusCode);
    return [
      for (final d in (j['documents'] as List? ?? []))
        _member(d as Map<String, dynamic>),
    ]..sort((a, b) => a.isOwner == b.isOwner ? a.email.compareTo(b.email) : (a.isOwner ? -1 : 1));
  }

  /// This user's team entry, or null when they are not on the team.
  Future<Member?> me() async {
    final email = user?.email ?? '';
    final res = await _send(() async =>
        _http.get(Uri.parse('${config._docsBase}/members/${Uri.encodeComponent(email)}'), headers: await _headers()));
    if (res.statusCode == 404 || res.statusCode == 403) return null;
    final j = _decode(res);
    if (res.statusCode != 200) throw _error(j, res.statusCode);
    return _member(j);
  }

  Member _member(Map<String, dynamic> d) {
    final f = (d['fields'] as Map<String, dynamic>?) ?? {};
    String s(String k) => ((f[k] as Map?)?['stringValue'] as String?) ?? '';
    return Member(email: Uri.decodeComponent((d['name'] as String).split('/').last), name: s('name'), role: s('role'));
  }

  Future<void> setMember(Member m) async {
    final res = await _send(() async => _http.patch(Uri.parse('${config._docsBase}/members/${Uri.encodeComponent(m.email.toLowerCase())}'),
        headers: await _headers(),
        body: jsonEncode({
          'fields': {
            'name': {'stringValue': m.name},
            'role': {'stringValue': m.role},
          }
        })));
    if (res.statusCode != 200) throw _error(_decode(res), res.statusCode);
  }

  Future<void> removeMember(String email) async {
    final res = await _send(() async =>
        _http.delete(Uri.parse('${config._docsBase}/members/${Uri.encodeComponent(email)}'), headers: await _headers()));
    if (res.statusCode != 200) throw _error(_decode(res), res.statusCode);
  }

  // ---- Helpers ----

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    try {
      return await call().timeout(const Duration(seconds: 25));
    } on CloudError {
      rethrow;
    } catch (_) {
      throw CloudError('OFFLINE');
    }
  }

  Map<String, dynamic> _decode(http.Response r) {
    try {
      final v = jsonDecode(utf8.decode(r.bodyBytes));
      return v is Map<String, dynamic> ? v : {'value': v};
    } catch (_) {
      return {};
    }
  }

  CloudError _error(Map<String, dynamic> j, int status) {
    final e = j['error'];
    if (e is Map) {
      if (e['status'] == 'PERMISSION_DENIED') return CloudError('PERMISSION_DENIED', status);
      return CloudError('${e['message'] ?? e['status'] ?? 'Error $status'}', status);
    }
    if (e is String) return CloudError(e.toUpperCase(), status);
    return CloudError('Error $status', status);
  }
}
