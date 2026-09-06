import 'dart:io';

import 'package:flutter/foundation.dart';

import '../model/column_meta.dart';
import '../model/csv_table.dart';
import '../model/filter.dart';
import '../services/csv_loader.dart';
import '../services/csv_writer.dart';

class SortSpec {
  const SortSpec(this.column, {this.ascending = true});
  final int column;
  final bool ascending;
}

/// Everything the UI reads and mutates. One controller per window.
class AppController extends ChangeNotifier {
  CsvTable? _table;
  LoadOptions _options = const LoadOptions();
  bool _loading = false;
  String? _error;

  final List<FilterRule> _filters = <FilterRule>[];
  final List<SortSpec> _sorts = <SortSpec>[];
  String _quickSearch = '';

  List<int> _viewRows = <int>[];
  List<bool> _columnVisible = <bool>[];
  List<double> _columnWidths = <double>[];
  final Map<int, List<Object?>> _sortKeyCache = <int, List<Object?>>{};

  int? _selectedRow; // index into _viewRows
  bool _showInspector = false;

  CsvTable? get table => _table;
  LoadOptions get options => _options;
  bool get loading => _loading;
  String? get error => _error;
  bool get hasDocument => _table != null;

  List<FilterRule> get filters => List.unmodifiable(_filters);
  List<SortSpec> get sorts => List.unmodifiable(_sorts);
  String get quickSearch => _quickSearch;
  List<int> get viewRows => _viewRows;
  int get totalRows => _table?.rowCount ?? 0;
  int get visibleRowCount => _viewRows.length;
  bool get isFiltered => _filters.any((f) => f.enabled) || _quickSearch.isNotEmpty;

  bool get showInspector => _showInspector;
  int? get selectedViewIndex => _selectedRow;
  int? get selectedSourceRow =>
      (_selectedRow != null && _selectedRow! < _viewRows.length) ? _viewRows[_selectedRow!] : null;

  List<int> get visibleColumns {
    final result = <int>[];
    for (var i = 0; i < _columnVisible.length; i++) {
      if (_columnVisible[i]) result.add(i);
    }
    return result;
  }

  bool isColumnVisible(int index) => index < _columnVisible.length && _columnVisible[index];
  double columnWidth(int index) => index < _columnWidths.length ? _columnWidths[index] : 140;

  SortSpec? sortFor(int column) {
    for (final spec in _sorts) {
      if (spec.column == column) return spec;
    }
    return null;
  }

  int sortPriority(int column) {
    for (var i = 0; i < _sorts.length; i++) {
      if (_sorts[i].column == column) return i;
    }
    return -1;
  }

  // ---------------------------------------------------------------- loading

  Future<void> openPath(String path, {LoadOptions? options}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final loaded = await loadCsvFile(path, options ?? const LoadOptions());
      _adopt(loaded, options ?? const LoadOptions());
    } catch (e) {
      _error = 'Não foi possível abrir o arquivo: $e';
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> openBytes(Uint8List bytes, String fileName, {LoadOptions? options}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final loaded = await loadCsvBytes(bytes, fileName, options ?? const LoadOptions());
      _adopt(loaded, options ?? const LoadOptions());
    } catch (e) {
      _error = 'Não foi possível abrir o arquivo: $e';
      _loading = false;
      notifyListeners();
    }
  }

  /// Re-parses the current file with different delimiter / encoding / header
  /// settings, keeping filters and sorting when the columns still line up.
  Future<void> reload(LoadOptions options) async {
    final path = _table?.filePath;
    if (path == null) return;
    final previousNames = _table!.columns.map((c) => c.name).toList();
    final previousFilters = List<FilterRule>.from(_filters);
    final previousSorts = List<SortSpec>.from(_sorts);
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final loaded = await loadCsvFile(path, options);
      _adopt(loaded, options);
      final sameShape = loaded.columns.length == previousNames.length &&
          List.generate(previousNames.length, (i) => loaded.columns[i].name == previousNames[i])
              .every((ok) => ok);
      if (sameShape) {
        _filters
          ..clear()
          ..addAll(previousFilters);
        _sorts
          ..clear()
          ..addAll(previousSorts);
        _recompute();
        notifyListeners();
      }
    } catch (e) {
      _error = 'Não foi possível recarregar o arquivo: $e';
      _loading = false;
      notifyListeners();
    }
  }

  void _adopt(CsvTable loaded, LoadOptions options) {
    _table = loaded;
    _options = options.copyWith(delimiter: loaded.delimiter, hasHeaderRow: loaded.hasHeaderRow);
    _filters.clear();
    _sorts.clear();
    _quickSearch = '';
    _selectedRow = null;
    _sortKeyCache.clear();
    _columnVisible = List<bool>.filled(loaded.columnCount, true);
    _columnWidths = _measureColumns(loaded);
    _loading = false;
    _recompute();
    notifyListeners();
  }

  void closeDocument() {
    _table = null;
    _filters.clear();
    _sorts.clear();
    _viewRows = <int>[];
    _columnVisible = <bool>[];
    _columnWidths = <double>[];
    _sortKeyCache.clear();
    _quickSearch = '';
    _selectedRow = null;
    _error = null;
    notifyListeners();
  }

  /// Width heuristic: header plus a sample of the values, clamped so that one
  /// long free-text column cannot push everything else off screen.
  List<double> _measureColumns(CsvTable table) {
    const perChar = 7.6;
    final sample = table.rowCount < 200 ? table.rowCount : 200;
    return List<double>.generate(table.columnCount, (c) {
      var longest = table.columns[c].name.length + 4;
      for (var r = 0; r < sample; r++) {
        final length = table.cell(r, c).length;
        if (length > longest) longest = length;
      }
      final width = longest * perChar + 24;
      return width.clamp(70.0, 340.0);
    });
  }

  // ------------------------------------------------------------------- view

  void setColumnWidth(int index, double width) {
    if (index >= _columnWidths.length) return;
    _columnWidths[index] = width.clamp(48.0, 1200.0);
    notifyListeners();
  }

  void setColumnVisible(int index, bool visible) {
    if (index >= _columnVisible.length) return;
    // Never hide the last visible column: an empty grid is a dead end.
    if (!visible && visibleColumns.length <= 1) return;
    _columnVisible[index] = visible;
    notifyListeners();
  }

  void showAllColumns() {
    for (var i = 0; i < _columnVisible.length; i++) {
      _columnVisible[i] = true;
    }
    notifyListeners();
  }

  void toggleInspector() {
    _showInspector = !_showInspector;
    notifyListeners();
  }

  void selectViewRow(int? index) {
    _selectedRow = index;
    notifyListeners();
  }

  void setQuickSearch(String value) {
    if (_quickSearch == value) return;
    _quickSearch = value;
    _recompute();
    notifyListeners();
  }

  // ---------------------------------------------------------------- sorting

  /// Click cycles ascending → descending → unsorted. With [additive] (shift)
  /// the column is appended as a secondary sort key instead of replacing it.
  void toggleSort(int column, {bool additive = false}) {
    final existingIndex = sortPriority(column);
    if (!additive) {
      if (existingIndex == 0 && _sorts.length == 1) {
        final current = _sorts.first;
        if (current.ascending) {
          _sorts[0] = SortSpec(column, ascending: false);
        } else {
          _sorts.clear();
        }
      } else {
        _sorts
          ..clear()
          ..add(SortSpec(column, ascending: true));
      }
    } else {
      if (existingIndex >= 0) {
        final current = _sorts[existingIndex];
        if (current.ascending) {
          _sorts[existingIndex] = SortSpec(column, ascending: false);
        } else {
          _sorts.removeAt(existingIndex);
        }
      } else {
        _sorts.add(SortSpec(column, ascending: true));
      }
    }
    _recompute();
    notifyListeners();
  }

  void setSort(int column, bool ascending) {
    _sorts
      ..clear()
      ..add(SortSpec(column, ascending: ascending));
    _recompute();
    notifyListeners();
  }

  void clearSort() {
    _sorts.clear();
    _recompute();
    notifyListeners();
  }

  // ---------------------------------------------------------------- filters

  void addFilter(FilterRule rule) {
    _filters.add(rule);
    _recompute();
    notifyListeners();
  }

  void updateFilter(int index, FilterRule rule) {
    if (index < 0 || index >= _filters.length) return;
    _filters[index] = rule;
    _recompute();
    notifyListeners();
  }

  void removeFilter(int index) {
    if (index < 0 || index >= _filters.length) return;
    _filters.removeAt(index);
    _recompute();
    notifyListeners();
  }

  void toggleFilterEnabled(int index) {
    if (index < 0 || index >= _filters.length) return;
    _filters[index] = _filters[index].copyWith(enabled: !_filters[index].enabled);
    _recompute();
    notifyListeners();
  }

  void clearFilters() {
    if (_filters.isEmpty && _quickSearch.isEmpty) return;
    _filters.clear();
    _quickSearch = '';
    _recompute();
    notifyListeners();
  }

  // ------------------------------------------------------------- pipeline

  void _recompute() {
    final table = _table;
    if (table == null) {
      _viewRows = <int>[];
      return;
    }
    final program = FilterProgram.compile(_filters, table.columns);
    final needle = _quickSearch.toLowerCase();
    final rows = table.rows;
    final result = <int>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (!program.matches(row)) continue;
      if (needle.isNotEmpty && !_rowContains(row, needle)) continue;
      result.add(i);
    }
    if (_sorts.isNotEmpty) {
      final keySets = <List<Object?>>[];
      for (final spec in _sorts) {
        keySets.add(_sortKeys(table, spec.column));
      }
      result.sort((a, b) {
        for (var s = 0; s < _sorts.length; s++) {
          final keys = keySets[s];
          final comparison = _compareKeys(keys[a], keys[b]);
          if (comparison != 0) {
            return _sorts[s].ascending ? comparison : -comparison;
          }
        }
        return a.compareTo(b); // stable: keep original file order on ties
      });
    }
    _viewRows = result;
    if (_selectedRow != null && _selectedRow! >= _viewRows.length) {
      _selectedRow = _viewRows.isEmpty ? null : _viewRows.length - 1;
    }
  }

  bool _rowContains(List<String> row, String needle) {
    for (final cell in row) {
      if (cell.toLowerCase().contains(needle)) return true;
    }
    return false;
  }

  /// Sort keys are computed once per column and reused, which keeps repeated
  /// sorts on large files instant.
  List<Object?> _sortKeys(CsvTable table, int column) {
    final cached = _sortKeyCache[column];
    if (cached != null) return cached;
    final meta = table.columns[column];
    final keys = List<Object?>.filled(table.rowCount, null);
    for (var i = 0; i < table.rowCount; i++) {
      final raw = table.cell(i, column);
      if (raw.trim().isEmpty) {
        keys[i] = null;
        continue;
      }
      switch (meta.type) {
        case ColumnType.number:
          keys[i] = meta.number(raw);
          break;
        case ColumnType.date:
          keys[i] = meta.date(raw)?.millisecondsSinceEpoch.toDouble();
          break;
        case ColumnType.text:
          keys[i] = raw.toLowerCase();
          break;
      }
    }
    _sortKeyCache[column] = keys;
    return keys;
  }

  int _compareKeys(Object? a, Object? b) {
    if (a == null || b == null) {
      if (a == null && b == null) return 0;
      return a == null ? 1 : -1; // blanks last
    }
    if (a is double && b is double) return a.compareTo(b);
    if (a is String && b is String) return a.compareTo(b);
    return a.toString().compareTo(b.toString());
  }

  // ------------------------------------------------------------------ export

  String exportCsv({bool onlyVisibleColumns = true}) {
    final table = _table!;
    final columns = onlyVisibleColumns
        ? visibleColumns
        : List<int>.generate(table.columnCount, (i) => i);
    return encodeCsv(
      table: table,
      rowIndices: _viewRows,
      columnIndices: columns,
      delimiter: table.delimiter,
      includeHeader: true,
    );
  }

  Future<void> writeExport(String path, {bool onlyVisibleColumns = true}) async {
    final content = exportCsv(onlyVisibleColumns: onlyVisibleColumns);
    await File(path).writeAsString(content);
  }

  /// Distinct values for the value-picker filter, computed on demand.
  List<String> distinctValues(int column) => _table?.distinctValues(column) ?? const <String>[];
}
