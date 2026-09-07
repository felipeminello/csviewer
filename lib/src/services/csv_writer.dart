import '../model/column_meta.dart';
import '../model/csv_table.dart';

/// Header line for the given columns.
String encodeHeader(List<ColumnMeta> columns, List<int> columnIndices, String delimiter) {
  return '${columnIndices.map((c) => escapeCsvField(columns[c].name, delimiter)).join(delimiter)}\n';
}

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
      columnIndices.map((c) => escapeCsvField(table.columns[c].name, delimiter)).join(delimiter),
    );
  }
  for (final r in rowIndices) {
    buffer.writeln(
      columnIndices.map((c) => escapeCsvField(table.cell(r, c), delimiter)).join(delimiter),
    );
  }
  return buffer.toString();
}

String escapeCsvField(String value, String delimiter) {
  final needsQuotes = value.contains(delimiter) ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuotes) return value;
  return '"${value.replaceAll('"', '""')}"';
}
