import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Saves [bytes] as a file. On iPad Safari this offers "Download" to the Files app.
Future<void> downloadFile(String name, Uint8List bytes, String mime) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = name;
  web.document.body!.append(a);
  a.click();
  a.remove();
  Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}

/// Lets the user choose a file (e.g. a backup from the Files app) and returns its text.
Future<String?> pickTextFile() {
  final done = Completer<String?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.json,application/json';
  input.onchange = (web.Event _) {
    final file = input.files?.item(0);
    if (file == null) return done.complete(null);
    file.text().toDart.then((t) => done.complete(t.toDart), onError: (_) => done.complete(null));
  }.toJS;
  input.click();
  return done.future;
}

/// Asks Safari to keep this app's data instead of clearing it when space runs low.
Future<bool> requestPersistentStorage() async {
  try {
    return (await web.window.navigator.storage.persist().toDart).toDart;
  } catch (_) {
    return false;
  }
}

/// How a [shareFile] call ended.
enum ShareResult { shared, cancelled, needsTap, unsupported }

/// Opens the device's share sheet (WhatsApp, Mail, Telegram, AirDrop, Files ...) with the file.
/// Safari only allows this straight after a tap: when the file took too long to make, the result
/// is [ShareResult.needsTap] and the caller should offer a button that calls this again.
Future<ShareResult> shareFile(String name, Uint8List bytes, String mime) async {
  try {
    final nav = web.window.navigator;
    final file = web.File([bytes.toJS].toJS, name, web.FilePropertyBag(type: mime));
    final data = web.ShareData(files: [file].toJS, title: name);
    if (!nav.canShare(data)) return ShareResult.unsupported;
    await nav.share(data).toDart;
    return ShareResult.shared;
  } catch (e) {
    final s = e.toString();
    if (s.contains('AbortError')) return ShareResult.cancelled;
    if (s.contains('NotAllowedError')) return ShareResult.needsTap;
    return ShareResult.unsupported;
  }
}
