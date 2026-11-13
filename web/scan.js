// Camera barcode / QR reading for the app, on top of the bundled ZXing library (works offline).
window.storeScan = (function () {
  var reader = null;
  return {
    start: function (video, onCode, onError) {
      try {
        if (!navigator.mediaDevices || !window.ZXing) { onError('no-camera'); return; }
        reader = new ZXing.BrowserMultiFormatReader();
        reader.decodeFromConstraints({ audio: false, video: { facingMode: { ideal: 'environment' } } }, video,
          function (result) { if (result) onCode(result.getText()); })
          .catch(function (e) { onError(String((e && (e.name || e.message)) || e)); });
      } catch (e) { onError(String(e)); }
    },
    stop: function () { if (reader) { try { reader.reset(); } catch (e) {} reader = null; } }
  };
})();
