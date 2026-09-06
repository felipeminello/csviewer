/// Column typing used for sorting and for comparison filters.
enum ColumnType { text, number, date }

/// How numbers are written in a column: `1,234.56` (dot decimal) or
/// `1.234,56` (comma decimal, common in pt-BR / European exports).
enum NumberStyle { dot, comma }

class ColumnMeta {
  const ColumnMeta({
    required this.index,
    required this.name,
    this.type = ColumnType.text,
    this.numberStyle = NumberStyle.dot,
  });

  final int index;
  final String name;
  final ColumnType type;
  final NumberStyle numberStyle;

  bool get isNumeric => type == ColumnType.number;

  ColumnMeta copyWith({String? name, ColumnType? type, NumberStyle? numberStyle}) {
    return ColumnMeta(
      index: index,
      name: name ?? this.name,
      type: type ?? this.type,
      numberStyle: numberStyle ?? this.numberStyle,
    );
  }

  /// Parses [raw] as a number honouring the column's detected style.
  double? number(String raw) => parseNumber(raw, numberStyle);

  /// Parses [raw] as a date honouring the formats this app recognises.
  DateTime? date(String raw) => parseDate(raw);
}

/// `1,234.56` style: comma may only appear as a thousands separator.
final RegExp _dotNumber = RegExp(r'^[+-]?(\d{1,3}(,\d{3})+|\d+)(\.\d+)?([eE][+-]?\d+)?$');

/// `1.234,56` style: dot may only appear as a thousands separator.
final RegExp _commaNumber = RegExp(r'^[+-]?(\d{1,3}(\.\d{3})+|\d+)(,\d+)?([eE][+-]?\d+)?$');

/// Parses a numeric cell in the given style, tolerating currency symbols,
/// percent signs, thin spaces and accounting parentheses. Returns null when the
/// text is not a number *in that style*, which is what lets column type
/// detection tell `10,5` (comma decimal) from `1,050` (thousands separator).
double? parseNumber(String raw, NumberStyle style) {
  var s = raw.trim();
  if (s.isEmpty) return null;
  s = s.replaceAll('\u00A0', '').replaceAll('\u202F', '').replaceAll(' ', '');
  s = s.replaceAll(RegExp(r'^[R\$€£¥]+'), '');
  if (s.endsWith('%')) s = s.substring(0, s.length - 1);
  var negative = false;
  if (s.startsWith('(') && s.endsWith(')')) {
    negative = true;
    s = s.substring(1, s.length - 1);
  }
  if (s.isEmpty) return null;
  if (style == NumberStyle.dot) {
    if (!_dotNumber.hasMatch(s)) return null;
    s = s.replaceAll(',', '');
  } else {
    if (!_commaNumber.hasMatch(s)) return null;
    s = s.replaceAll('.', '').replaceAll(',', '.');
  }
  final value = double.tryParse(s);
  if (value == null) return null;
  return negative ? -value : value;
}

final RegExp _isoLike = RegExp(r'^\d{4}-\d{2}-\d{2}');
final RegExp _slashed = RegExp(
  r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?)?$',
);

/// Recognises ISO-8601 and `dd/MM/yyyy` style dates (day-first, as used in
/// pt-BR exports). Returns null when the text is not a date.
DateTime? parseDate(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  if (_isoLike.hasMatch(s)) {
    final parsed = DateTime.tryParse(s.replaceFirst(' ', 'T'));
    if (parsed != null) return parsed;
  }
  final m = _slashed.firstMatch(s);
  if (m == null) return null;
  var day = int.parse(m.group(1)!);
  var month = int.parse(m.group(2)!);
  var year = int.parse(m.group(3)!);
  if (year < 100) year += year < 70 ? 2000 : 1900;
  if (month > 12 && day <= 12) {
    final swap = day;
    day = month;
    month = swap;
  }
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final hour = int.tryParse(m.group(4) ?? '') ?? 0;
  final minute = int.tryParse(m.group(5) ?? '') ?? 0;
  final second = int.tryParse(m.group(6) ?? '') ?? 0;
  return DateTime(year, month, day, hour, minute, second);
}
