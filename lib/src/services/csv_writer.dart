import '../model/csv_table.dart';

/// Serialises the given rows back to CSV, quoting only where required.
String encodeCsv({
  required CsvTable table,
  required List<int> rowIndices,
  required List<int> columnIndices,
  required String delimiter,
  bool includeHeader = true,
}) {
  final buffer = StringBuffer();
  if (includeHeader) {
    buffer.writeln(
      columnIndices.map((c) => _escape(table.columns[c].name, delimiter)).join(delimiter),
    );
  }
  for (final r in rowIndices) {
    buffer.writeln(
      columnIndices.map((c) => _escape(table.cell(r, c), delimiter)).join(delimiter),
    );
  }
  return buffer.toString();
}

String _escape(String value, String delimiter) {
  final needsQuotes = value.contains(delimiter) ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuotes) return value;
  return '"${value.replaceAll('"', '""')}"';
}
