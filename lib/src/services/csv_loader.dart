import 'dart:io';

import 'package:flutter/foundation.dart';

import '../model/csv_table.dart';
import 'csv_parser.dart';

class LoadOptions {
  const LoadOptions({
    this.delimiter,
    this.encoding = encodingAuto,
    this.hasHeaderRow = true,
  });

  /// Null means "detect from the file".
  final String? delimiter;
  final String encoding;
  final bool hasHeaderRow;

  LoadOptions copyWith({
    String? delimiter,
    bool clearDelimiter = false,
    String? encoding,
    bool? hasHeaderRow,
  }) {
    return LoadOptions(
      delimiter: clearDelimiter ? null : (delimiter ?? this.delimiter),
      encoding: encoding ?? this.encoding,
      hasHeaderRow: hasHeaderRow ?? this.hasHeaderRow,
    );
  }
}

class _LoadRequest {
  const _LoadRequest(this.path, this.bytes, this.fileName, this.options);
  final String? path;
  final Uint8List? bytes;
  final String fileName;
  final LoadOptions options;
}

/// Reads, decodes and parses a CSV file off the UI thread.
Future<CsvTable> loadCsvFile(String path, LoadOptions options) {
  final name = path.split(Platform.pathSeparator).last;
  return compute(_load, _LoadRequest(path, null, name, options));
}

Future<CsvTable> loadCsvBytes(Uint8List bytes, String fileName, LoadOptions options) {
  return compute(_load, _LoadRequest(null, bytes, fileName, options));
}

CsvTable _load(_LoadRequest request) {
  final bytes = request.bytes ?? File(request.path!).readAsBytesSync();
  final decoded = decodeBytes(bytes, encoding: request.options.encoding);
  final delimiter = request.options.delimiter ?? detectDelimiter(decoded.text);
  final raw = parseCsvString(decoded.text, delimiter);

  final warnings = <String>[];
  if (raw.isEmpty) {
    return CsvTable(
      columns: const [],
      rows: const [],
      delimiter: delimiter,
      encodingName: decoded.encodingName,
      fileName: request.fileName,
      filePath: request.path,
      fileSizeBytes: bytes.length,
      hasHeaderRow: request.options.hasHeaderRow,
      warnings: const ['O arquivo está vazio.'],
    );
  }

  List<String> names;
  List<List<String>> rows;
  if (request.options.hasHeaderRow) {
    names = raw.first.map((e) => e.trim()).toList();
    rows = raw.length > 1 ? raw.sublist(1) : <List<String>>[];
  } else {
    names = <String>[];
    rows = raw;
  }

  var widest = names.length;
  for (final row in rows) {
    if (row.length > widest) widest = row.length;
  }
  for (var i = names.length; i < widest; i++) {
    names.add(request.options.hasHeaderRow ? 'Coluna ${i + 1}' : 'Coluna ${i + 1}');
  }
  // Empty or duplicated headers make columns impossible to tell apart.
  final used = <String, int>{};
  for (var i = 0; i < names.length; i++) {
    var name = names[i].trim();
    if (name.isEmpty) name = 'Coluna ${i + 1}';
    final seen = used[name.toLowerCase()];
    if (seen != null) {
      used[name.toLowerCase()] = seen + 1;
      name = '$name (${seen + 1})';
    } else {
      used[name.toLowerCase()] = 1;
    }
    names[i] = name;
  }

  var ragged = 0;
  for (final row in rows) {
    if (row.length != names.length) ragged++;
  }
  if (ragged > 0) {
    warnings.add('$ragged linha(s) com número de campos diferente do cabeçalho.');
  }

  return CsvTable(
    columns: inferColumns(names, rows),
    rows: rows,
    delimiter: delimiter,
    encodingName: decoded.encodingName,
    fileName: request.fileName,
    filePath: request.path,
    fileSizeBytes: bytes.length,
    hasHeaderRow: request.options.hasHeaderRow,
    warnings: warnings,
  );
}
