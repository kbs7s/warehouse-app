import 'package:flutter/widgets.dart';

bool get scannerAvailable => false;
Widget scannerView({required void Function(String) onCode, required void Function(String) onError}) => const SizedBox.shrink();
void stopScanner() {}
