import 'dart:typed_data';

Future<void> downloadFile(String name, Uint8List bytes, String mime) async {}
Future<String?> pickTextFile() async => null;
Future<bool> requestPersistentStorage() async => false;

enum ShareResult { shared, cancelled, needsTap, unsupported }

Future<ShareResult> shareFile(String name, Uint8List bytes, String mime) async => ShareResult.unsupported;
