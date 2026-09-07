import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../model/column_meta.dart';
import '../model/csv_table.dart';
import '../model/filter.dart';
import '../model/sort_spec.dart';
import '../services/csv_loader.dart';
import '../services/csv_worker.dart';
import '../services/csv_writer.dart';

/// A row of the current view, together with the line it came from.
class LoadedRow {
  const LoadedRow(this.values, this.sourceRow);
  final List<String> values;
  final int sourceRow;

  String cell(int column) => column < values.length ? values[column] : '';
}

/// The data behind the grid. Two implementations: everything in memory for
/// ordinary files, and an indexed, block-at-a-time reader for huge ones.
///
/// Notifies listeners when rows requested earlier become available.
abstract class CsvSource extends ChangeNotifier {
  String get fileName;
  String? get filePath;
  int get fileSizeBytes;
  String get delimiter;
  String get encodingName;
  bool get hasHeaderRow;
  List<ColumnMeta> get columns;
  List<String> get warnings;

  /// True when the file is read from disk on demand instead of held in memory.
  bool get isStreaming;

  /// Records in the file. Grows while a large file is still being indexed.
  int get totalRows;

  /// Records after filters — what the grid shows.
  int get viewRowCount;

  bool get indexing;
  double get indexProgress;

  /// 0 means "no limit".
  int get sortLimit;

  int get columnCount => columns.length;

  /// Row for a view position, or null when it still has to be read from disk.
  LoadedRow? rowIfReady(int viewIndex);

  /// Asks for a range of view positions to be brought in.
  void ensureRange(int start, int end);

  Future<LoadedRow?> rowAt(int viewIndex);

  Future<ViewResult> applyView(
    List<FilterRule> filters,
    String search,
    List<SortSpec> sorts, {
    void Function(double)? onProgress,
  });

  Future<List<String>> distinctValues(int column, {int limit = 10000});

  Future<int> exportTo(String path, List<int> columns);
}

// ------------------------------------------------------------------- memory

/// Whole file in memory: every operation is immediate.
class MemoryCsvSource extends CsvSource {
  MemoryCsvSource(this._table) {
    _view = List<int>.generate(_table.rowCount, (i) => i);
  }

  final CsvTable _table;
  late List<int> _view;
  final Map<int, List<Object?>> _sortKeys = <int, List<Object?>>{};

  CsvTable get table => _table;

  @override
  String get fileName => _table.fileName;
  @override
  String? get filePath => _table.filePath;
  @override
  int get fileSizeBytes => _table.fileSizeBytes;
  @override
  String get delimiter => _table.delimiter;
  @override
  String get encodingName => _table.encodingName;
  @override
  bool get hasHeaderRow => _table.hasHeaderRow;
  @override
  List<ColumnMeta> get columns => _table.columns;
  @override
  List<String> get warnings => _table.warnings;
  @override
  bool get isStreaming => false;
  @override
  int get totalRows => _table.rowCount;
  @override
  int get viewRowCount => _view.length;
  @override
  bool get indexing => false;
  @override
  double get indexProgress => 1;
  @override
  int get sortLimit => 0;

  @override
  LoadedRow? rowIfReady(int viewIndex) {
    if (viewIndex < 0 || viewIndex >= _view.length) return null;
    final row = _view[viewIndex];
    return LoadedRow(_table.rows[row], row);
  }

  @override
  void ensureRange(int start, int end) {}

  @override
  Future<LoadedRow?> rowAt(int viewIndex) async => rowIfReady(viewIndex);

  @override
  Future<ViewResult> applyView(
    List<FilterRule> filters,
    String search,
    List<SortSpec> sorts, {
    void Function(double)? onProgress,
  }) async {
    final program = FilterProgram.compile(filters, _table.columns);
    final needle = search.toLowerCase();
    final rows = _table.rows;
    final result = <int>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (!program.matches(row)) continue;
      if (needle.isNotEmpty && !_contains(row, needle)) continue;
      result.add(i);
    }
    if (sorts.isNotEmpty) {
      final keySets = [for (final spec in sorts) _keysFor(spec.column)];
      result.sort((a, b) {
        for (var s = 0; s < sorts.length; s++) {
          final comparison = compareSortKeys(keySets[s][a], keySets[s][b]);
          if (comparison != 0) return sorts[s].ascending ? comparison : -comparison;
        }
        return a.compareTo(b); // stable: keep file order on ties
      });
    }
    _view = result;
    notifyListeners();
    return ViewResult(rowCount: _view.length);
  }

  bool _contains(List<String> row, String needle) {
    for (final cell in row) {
      if (cell.toLowerCase().contains(needle)) return true;
    }
    return false;
  }

  /// Sort keys are built once per column and reused across sorts.
  List<Object?> _keysFor(int column) {
    final cached = _sortKeys[column];
    if (cached != null) return cached;
    final meta = _table.columns[column];
    final keys = List<Object?>.generate(
      _table.rowCount,
      (i) => sortKeyOf(_table.rows[i], column, meta),
    );
    _sortKeys[column] = keys;
    return keys;
  }

  @override
  Future<List<String>> distinctValues(int column, {int limit = 10000}) async =>
      _table.distinctValues(column, limit: limit);

  @override
  Future<int> exportTo(String path, List<int> columns) async {
    final content = encodeCsv(
      table: _table,
      rowIndices: _view,
      columnIndices: columns,
      delimiter: _table.delimiter,
    );
    await File(path).writeAsString(content);
    return _view.length;
  }
}

// ---------------------------------------------------------------- streaming

/// Rows per fetched window. Small enough to arrive quickly, big enough that a
/// screenful of scrolling rarely needs more than one request.
const int kWindowRows = 128;
const int _maxCachedWindows = 96;

/// Reads a large file from disk on demand: an offset index is built once in a
/// background isolate, and only the visible records are ever decoded.
class StreamingCsvSource extends CsvSource {
  StreamingCsvSource._(this._worker, this._path, this._open, this._hasHeader, this._sortLimit) {
    _worker.onIndexProgress = _onIndexProgress;
  }

  static Future<StreamingCsvSource> open(
    String path,
    LoadOptions options, {
    int sortLimit = kMaxSortableRows,
  }) async {
    final worker = await CsvWorkerClient.spawn();
    try {
      final result = await worker.open(
        path,
        delimiter: options.delimiter,
        encoding: options.encoding,
        hasHeader: options.hasHeaderRow,
        sortLimit: sortLimit,
      );
      return StreamingCsvSource._(worker, path, result, options.hasHeaderRow, sortLimit);
    } catch (_) {
      worker.dispose();
      rethrow;
    }
  }

  final CsvWorkerClient _worker;
  final String _path;
  final OpenResult _open;
  final bool _hasHeader;
  final int _sortLimit;

  final LinkedHashMap<int, RowWindow> _windows = LinkedHashMap<int, RowWindow>();
  final Set<int> _loading = <int>{};

  int _totalRows = 0;
  int _viewRowCount = 0;
  bool _indexing = true;
  double _indexProgress = 0;
  bool _viewIsFiltered = false;
  bool _disposed = false;

  @override
  String get fileName => _path.split(Platform.pathSeparator).last;
  @override
  String? get filePath => _path;
  @override
  int get fileSizeBytes => _open.fileSize;
  @override
  String get delimiter => _open.delimiter;
  @override
  String get encodingName => _open.encodingName;
  @override
  bool get hasHeaderRow => _hasHeader;
  @override
  List<ColumnMeta> get columns => _open.columns;
  @override
  List<String> get warnings => _open.warnings;
  @override
  bool get isStreaming => true;
  @override
  int get totalRows => _totalRows;
  @override
  int get viewRowCount => _viewRowCount;
  @override
  bool get indexing => _indexing;
  @override
  double get indexProgress => _indexProgress;
  @override
  int get sortLimit => _sortLimit;

  void _onIndexProgress(IndexProgress progress) {
    if (_disposed) return;
    _totalRows = progress.rows;
    _indexProgress = progress.totalBytes == 0 ? 1 : progress.bytesRead / progress.totalBytes;
    _indexing = !progress.done;
    // While unfiltered, the view simply follows the file.
    if (!_viewIsFiltered) _viewRowCount = _totalRows;
    notifyListeners();
  }

  @override
  LoadedRow? rowIfReady(int viewIndex) {
    if (viewIndex < 0 || viewIndex >= _viewRowCount) return null;
    final windowStart = (viewIndex ~/ kWindowRows) * kWindowRows;
    final window = _windows[windowStart];
    if (window == null) return null;
    final offset = viewIndex - windowStart;
    if (offset >= window.rows.length) return null;
    return LoadedRow(window.rows[offset], window.sourceRows[offset]);
  }

  @override
  void ensureRange(int start, int end) {
    if (_disposed) return;
    final first = (start.clamp(0, _viewRowCount) ~/ kWindowRows) * kWindowRows;
    final last = (end.clamp(0, _viewRowCount) ~/ kWindowRows) * kWindowRows;
    for (var windowStart = first; windowStart <= last; windowStart += kWindowRows) {
      if (windowStart >= _viewRowCount) break;
      if (_windows.containsKey(windowStart) || _loading.contains(windowStart)) continue;
      _fetch(windowStart);
    }
  }

  Future<void> _fetch(int windowStart) async {
    _loading.add(windowStart);
    try {
      final window = await _worker.window(windowStart, kWindowRows);
      if (_disposed) return;
      _windows[windowStart] = window;
      while (_windows.length > _maxCachedWindows) {
        _windows.remove(_windows.keys.first);
      }
      notifyListeners();
    } catch (_) {
      // A window that fails (file replaced, worker gone) is simply retried the
      // next time it scrolls into view.
    } finally {
      _loading.remove(windowStart);
    }
  }

  @override
  Future<LoadedRow?> rowAt(int viewIndex) async {
    final ready = rowIfReady(viewIndex);
    if (ready != null) return ready;
    if (viewIndex < 0 || viewIndex >= _viewRowCount) return null;
    final windowStart = (viewIndex ~/ kWindowRows) * kWindowRows;
    if (!_loading.contains(windowStart)) {
      await _fetch(windowStart);
    } else {
      // Wait for the in-flight request instead of asking twice.
      while (_loading.contains(windowStart)) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
    }
    return rowIfReady(viewIndex);
  }

  @override
  Future<ViewResult> applyView(
    List<FilterRule> filters,
    String search,
    List<SortSpec> sorts, {
    void Function(double)? onProgress,
  }) async {
    final result = await _worker.applyView(
      filters: filters,
      search: search,
      sorts: sorts,
      onProgress: onProgress,
    );
    if (_disposed || result.cancelled) return result;
    _viewIsFiltered = filters.any((f) => f.enabled) || search.isNotEmpty || sorts.isNotEmpty;
    _viewRowCount = result.rowCount;
    _windows.clear();
    _loading.clear();
    notifyListeners();
    return result;
  }

  @override
  Future<List<String>> distinctValues(int column, {int limit = 10000}) =>
      _worker.distinctValues(column, limit);

  @override
  Future<int> exportTo(String path, List<int> columns) => _worker.export(path, columns);

  @override
  void dispose() {
    _disposed = true;
    _worker.dispose();
    super.dispose();
  }
}

// ------------------------------------------------------------------ factory

/// Opens [path], choosing between the in-memory and the streaming reader.
///
/// Files above [kStreamingThresholdBytes] are indexed and read block by block,
/// so a multi-gigabyte CSV never has to fit in RAM.
Future<CsvSource> openCsvSource(
  String path,
  LoadOptions options, {
  int sortLimit = kMaxSortableRows,
}) async {
  final file = File(path);
  final size = await file.length();
  var mode = options.mode;
  if (mode == ReadMode.auto) {
    mode = size > kStreamingThresholdBytes ? ReadMode.streaming : ReadMode.memory;
  }
  if (mode == ReadMode.streaming && await _isUtf16(file, options.encoding)) {
    // The streaming reader works on bytes; UTF-16 files go through the
    // in-memory path instead.
    mode = ReadMode.memory;
  }
  if (mode == ReadMode.streaming) {
    return StreamingCsvSource.open(path, options, sortLimit: sortLimit);
  }
  final table = await loadCsvFile(path, options);
  if (size > kStreamingThresholdBytes) {
    table.warnings.add(
      'Arquivo de ${(size / (1024 * 1024)).round()} MB carregado inteiro em memória.',
    );
  }
  return MemoryCsvSource(table);
}

Future<bool> _isUtf16(File file, String encoding) async {
  if (encoding == 'UTF-16') return true;
  final handle = await file.open();
  try {
    final head = await handle.read(2);
    if (head.length < 2) return false;
    return (head[0] == 0xFF && head[1] == 0xFE) || (head[0] == 0xFE && head[1] == 0xFF);
  } finally {
    await handle.close();
  }
}
