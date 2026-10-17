/// English / Arabic text for the interface. The language is chosen in Settings (or on the
/// welcome screen) and kept on the device; the app rebuilds when it changes.
library;

/// True while the interface is in Arabic.
bool isAr = false;

/// The English or Arabic version of a piece of interface text.
String tx(String en, String ar) => isAr ? ar : en;

/// Month names as used in Iraq.
const arMonths = [
  'كانون الثاني', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران',
  'تموز', 'آب', 'أيلول', 'تشرين الأول', 'تشرين الثاني', 'كانون الأول',
];
const arMonthsShort = ['ك٢', 'شباط', 'آذار', 'نيسان', 'أيار', 'حزيران', 'تموز', 'آب', 'أيلول', 'ت١', 'ت٢', 'ك١'];
