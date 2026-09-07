import 'column_meta.dart';

/// An immutable, in-memory CSV document.
class CsvTable {
  CsvTable({
    required this.columns,
    required this.rows,
    required this.delimiter,
    required this.encodingName,
    required this.fileName,
    required this.filePath,
    required this.fileSizeBytes,
    required this.hasHeaderRow,
    List<String>? warnings,
  }) : warnings = List<String>.of(warnings ?? const <String>[]);

  final List<ColumnMeta> columns;
  final List<List<String>> rows;
  final String delimiter;
  final String encodingName;
  final String fileName;
  final String? filePath;
  final int fileSizeBytes;
  final bool hasHeaderRow;
  final List<String> warnings;

  int get rowCount => rows.length;
  int get columnCount => columns.length;

  /// Cell access that tolerates short rows (ragged CSVs are common).
  String cell(int rowIndex, int columnIndex) {
    final row = rows[rowIndex];
    return columnIndex < row.length ? row[columnIndex] : '';
  }

  /// Distinct values of a column, sorted, capped at [limit] entries.
  List<String> distinctValues(int columnIndex, {int limit = 10000}) {
    final seen = <String>{};
    for (final row in rows) {
      seen.add(columnIndex < row.length ? row[columnIndex] : '');
      if (seen.length >= limit) break;
    }
    final values = seen.toList();
    final meta = columns[columnIndex];
    values.sort((a, b) => compareValues(a, b, meta));
    return values;
  }
}

/// Type-aware comparison used by both sorting and range filters.
/// Empty values always sort last so that blanks do not bury real data.
int compareValues(String a, String b, ColumnMeta meta) {
  final aEmpty = a.trim().isEmpty;
  final bEmpty = b.trim().isEmpty;
  if (aEmpty || bEmpty) {
    if (aEmpty && bEmpty) return 0;
    return aEmpty ? 1 : -1;
  }
  switch (meta.type) {
    case ColumnType.number:
      final na = meta.number(a);
      final nb = meta.number(b);
      if (na != null && nb != null) return na.compareTo(nb);
      if (na != null) return -1;
      if (nb != null) return 1;
      break;
    case ColumnType.date:
      final da = meta.date(a);
      final db = meta.date(b);
      if (da != null && db != null) return da.compareTo(db);
      if (da != null) return -1;
      if (db != null) return 1;
      break;
    case ColumnType.text:
      break;
  }
  return a.toLowerCase().compareTo(b.toLowerCase());
}

/// Key used to order a row by [column]: a double for numbers and dates, a
/// case-folded string for text, and null for blanks (which sort last).
Object? sortKeyOf(List<String> row, int column, ColumnMeta meta) {
  final raw = column < row.length ? row[column] : '';
  if (raw.trim().isEmpty) return null;
  switch (meta.type) {
    case ColumnType.number:
      return meta.number(raw);
    case ColumnType.date:
      return meta.date(raw)?.millisecondsSinceEpoch.toDouble();
    case ColumnType.text:
      return raw.toLowerCase();
  }
}

int compareSortKeys(Object? a, Object? b) {
  if (a == null || b == null) {
    if (a == null && b == null) return 0;
    return a == null ? 1 : -1;
  }
  if (a is double && b is double) return a.compareTo(b);
  if (a is String && b is String) return a.compareTo(b);
  return a.toString().compareTo(b.toString());
}
