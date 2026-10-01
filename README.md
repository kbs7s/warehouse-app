# Warehouse app (Flutter web, for iPad Safari)

Offline replacement for the hospital supply department's Excel warehouse workbook. English UI, Arabic item names.

- **Data:** none is bundled. On a new iPad the app asks for a data file: the Excel import (`app_seed.json`, kept out of this repo because it has staff names and phone numbers) or a backup exported from the Backup tab. Data then lives in the browser (IndexedDB) on that iPad.
- **Offline:** `tool/make_sw.py` writes `sw.js` after each build, caching the app so it opens with no internet.
- **Publish:** pushing to `main` builds and deploys to GitHub Pages (`.github/workflows/pages.yml`).
- **Local build:** `flutter build web --release --no-web-resources-cdn && python3 tool/make_sw.py`
- **Tests:** `flutter test` (needs `seed/app_seed.json` locally): stock math matches Excel, receipts, reports, Excel export, PDF with Arabic.
- **Code:** `lib/store.dart` (data and stock rules), `lib/models.dart`, `lib/pdf.dart`, `lib/xlsx.dart`, `lib/export.dart`, `lib/screens/`.
