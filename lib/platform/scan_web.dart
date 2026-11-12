import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

@JS('storeScan.start')
external void _start(web.HTMLVideoElement video, JSFunction onCode, JSFunction onError);
@JS('storeScan.stop')
external void _stop();

bool get scannerAvailable => true;

/// The live camera picture. [onCode] is called for every barcode or QR code it reads.
Widget scannerView({required void Function(String) onCode, required void Function(String) onError}) => HtmlElementView.fromTagName(
      tagName: 'video',
      onElementCreated: (el) {
        final v = el as web.HTMLVideoElement;
        v.setAttribute('playsinline', 'true'); // iPhone and iPad: stay in the page, not full screen
        v.muted = true;
        v.style
          ..width = '100%'
          ..height = '100%'
          ..objectFit = 'cover';
        _start(v, ((JSString s) => onCode(s.toDart)).toJS, ((JSString s) => onError(s.toDart)).toJS);
      },
    );

void stopScanner() => _stop();
