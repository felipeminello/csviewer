import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/csv_source.dart';
import '../model/column_meta.dart';
import '../model/filter.dart';
import '../model/sort_spec.dart';
import '../services/csv_loader.dart';
import '../services/csv_worker.dart' show kMaxSortableRows;

export '../model/sort_spec.dart' show SortSpec;

/// Everything the UI reads and mutates. One controller per window.
///
/// It owns the filter chain, the sort keys, column visibility and the
/// selection; the rows themselves live in a [CsvSource], which is either the
/// whole file in memory or an indexed reader over a file too big for that.
class AppController extends ChangeNotifier {
  CsvSource? _source;
  LoadOptions _options = const LoadOptions();
  bool _loading = false;
  String? _error;
  String? _notice;

  bool _busy = false;
  double _busyProgress = 0;
  int _viewGeneration = 0;
  int _loadGeneration = 0;
  Timer? _viewDebounce;

  final List<FilterRule> _filters = <FilterRule>[];
  final List<SortSpec> _sorts = <SortSpec>[];
  String _quickSearch = '';

  List<bool> _columnVisible = <bool>[];
  List<double> _columnWidths = <double>[];
  bool _widthsMeasured = false;

  int? _selectedRowIndex; // position in the view
  LoadedRow? _selectedRow;
  bool _showInspector = false;

  CsvSource? get source => _source;
  LoadOptions get options => _options;
  bool get loading => _loading;
  String? get error => _error;
  String? get notice => _notice;
  bool get hasDocument => _source != null;

  bool get busy => _busy;
  double get busyProgress => _busyProgress;

  List<FilterRule> get filters => List.unmodifiable(_filters);
  List<SortSpec> get sorts => List.unmodifiable(_sorts);
  String get quickSearch => _quickSearch;

  List<ColumnMeta> get columns => _source?.columns ?? const <ColumnMeta>[];
  int get columnCount => columns.length;
  String get fileName => _source?.fileName ?? '';
  String? get filePath => _source?.filePath;
  String get delimiter => _source?.delimiter ?? ',';
  String get encodingName => _source?.encodingName ?? '';
  int get fileSizeBytes => _source?.fileSizeBytes ?? 0;
  bool get isStreaming => _source?.isStreaming ?? false;
  bool get indexing => _source?.indexing ?? false;
  double get indexProgress => _source?.indexProgress ?? 1;
  int get sortLimit => _source?.sortLimit ?? 0;

  int get totalRows => _source?.totalRows ?? 0;
  int get visibleRowCount => _source?.viewRowCount ?? 0;
  bool get isFiltered => _filters.any((f) => f.enabled) || _quickSearch.isNotEmpty;

  bool get showInspector => _showInspector;
  int? get selectedViewIndex => _selectedRowIndex;
  LoadedRow? get selectedRow => _selectedRow;

  /// Row at a view position, or null while it is still being read from disk.
  LoadedRow? rowIfReady(int viewIndex) => _source?.rowIfReady(viewIndex);

  /// Tells the source which rows the grid is about to paint.
  void ensureRange(int start, int end) => _source?.ensureRange(start, end);

  /// Row at a view position, reading it from disk if necessary.
  Future<LoadedRow?> rowAt(int viewIndex) async => _source?.rowAt(viewIndex);

  /// Completes once the file is fully indexed and no filter/sort pass is
  /// pending or running — i.e. the view on screen is final.
  Future<void> settle({Duration timeout = const Duration(seconds: 60)}) async {
    final deadline = DateTime.now().add(timeout);
    while (indexing || (_viewDebounce?.isActive ?? false) || _busy) {
      if (DateTime.now().isAfter(deadline)) return;
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

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

  Future<void> openPath(String path, {LoadOptions? options, int sortLimit = kMaxSortableRows}) async {
    final opts = options ?? const LoadOptions();
    final generation = ++_loadGeneration;
    _loading = true;
    _error = null;
    _notice = null;
    notifyListeners();
    try {
      final source = await openCsvSource(path, opts, sortLimit: sortLimit);
      if (_discardStaleLoad(generation, source)) return;
      _adopt(source, opts);
    } catch (e) {
      if (generation != _loadGeneration) return;
      _error = 'Não foi possível abrir o arquivo: $e';
      _loading = false;
      notifyListeners();
    }
  }

  /// Re-reads the current file with different delimiter / encoding / header /
  /// mode settings, keeping filters and sorting when the columns still match.
  Future<void> reload(LoadOptions options) async {
    final path = _source?.filePath;
    if (path == null) return;
    final previousNames = columns.map((c) => c.name).toList();
    final previousFilters = List<FilterRule>.from(_filters);
    final previousSorts = List<SortSpec>.from(_sorts);
    final previousSearch = _quickSearch;
    final generation = ++_loadGeneration;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final source = await openCsvSource(path, options);
      if (_discardStaleLoad(generation, source)) return;
      _adopt(source, options);
      final names = source.columns.map((c) => c.name).toList();
      final sameShape = names.length == previousNames.length &&
          List.generate(names.length, (i) => names[i] == previousNames[i]).every((ok) => ok);
      if (sameShape) {
        _filters
          ..clear()
          ..addAll(previousFilters);
        _sorts
          ..clear()
          ..addAll(previousSorts);
        _quickSearch = previousSearch;
        _scheduleView(immediate: true);
      }
    } catch (e) {
      if (generation != _loadGeneration) return;
      _error = 'Não foi possível recarregar o arquivo: $e';
      _loading = false;
      notifyListeners();
    }
  }

  void _adopt(CsvSource source, LoadOptions options) {
    _source?.removeListener(_onSourceChanged);
    _source?.dispose();
    _source = source;
    source.addListener(_onSourceChanged);
    _options = options.copyWith(delimiter: source.delimiter, hasHeaderRow: source.hasHeaderRow);
    _filters.clear();
    _sorts.clear();
    _quickSearch = '';
    _selectedRowIndex = null;
    _selectedRow = null;
    _columnVisible = List<bool>.filled(source.columnCount, true);
    _columnWidths = _defaultWidths(source);
    _widthsMeasured = false;
    _busy = false;
    _loading = false;
    _measureFromLoadedRows();
    notifyListeners();
  }

  /// A file that finished opening after it was closed, or after another one
  /// was asked for, is thrown away instead of replacing what is on screen.
  bool _discardStaleLoad(int generation, CsvSource source) {
    if (generation == _loadGeneration) return false;
    source.dispose();
    return true;
  }

  /// Drops the file and everything tied to it, leaving the controller as it
  /// is right after the app starts. Opens and filter passes still running are
  /// discarded when they finish.
  void closeDocument() {
    _loadGeneration++;
    _viewGeneration++;
    _viewDebounce?.cancel();
    _viewDebounce = null;
    _source?.removeListener(_onSourceChanged);
    _source?.dispose();
    _source = null;
    _options = const LoadOptions();
    _loading = false;
    _error = null;
    _notice = null;
    _busy = false;
    _busyProgress = 0;
    _filters.clear();
    _sorts.clear();
    _quickSearch = '';
    _columnVisible = <bool>[];
    _columnWidths = <double>[];
    _widthsMeasured = false;
    _selectedRowIndex = null;
    _selectedRow = null;
    _showInspector = false;
    notifyListeners();
  }

  void _onSourceChanged() {
    _measureFromLoadedRows();
    notifyListeners();
  }

  List<double> _defaultWidths(CsvSource source) {
    return List<double>.generate(source.columnCount, (c) {
      final width = (source.columns[c].name.length + 6) * 7.6 + 24;
      return width.clamp(70.0, 340.0);
    });
  }

  /// Column widths follow the data, so they are measured from the first rows
  /// that actually arrive — immediately in memory mode, after the first window
  /// lands when streaming.
  void _measureFromLoadedRows() {
    final source = _source;
    if (source == null || _widthsMeasured) return;
    final sample = math.min(source.viewRowCount, 200);
    if (sample == 0) return;
    final longest = List<int>.generate(source.columnCount, (c) => source.columns[c].name.length + 4);
    var seen = 0;
    for (var i = 0; i < sample; i++) {
      final row = source.rowIfReady(i);
      if (row == null) continue;
      seen++;
      for (var c = 0; c < source.columnCount; c++) {
        final length = row.cell(c).length;
        if (length > longest[c]) longest[c] = length;
      }
    }
    if (seen == 0) return;
    _columnWidths = List<double>.generate(
      source.columnCount,
      (c) => (longest[c] * 7.6 + 24).clamp(70.0, 340.0),
    );
    _widthsMeasured = true;
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
    _selectedRowIndex = index;
    _selectedRow = index == null ? null : _source?.rowIfReady(index);
    notifyListeners();
    if (index != null && _selectedRow == null) _loadSelected(index);
  }

  Future<void> _loadSelected(int index) async {
    final row = await _source?.rowAt(index);
    if (_selectedRowIndex != index) return;
    _selectedRow = row;
    notifyListeners();
  }

  void setQuickSearch(String value) {
    if (_quickSearch == value) return;
    _quickSearch = value;
    notifyListeners();
    _scheduleView();
  }

  void clearNotice() {
    if (_notice == null) return;
    _notice = null;
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
    _scheduleView(immediate: true);
  }

  void setSort(int column, bool ascending) {
    _sorts
      ..clear()
      ..add(SortSpec(column, ascending: ascending));
    _scheduleView(immediate: true);
  }

  void clearSort() {
    if (_sorts.isEmpty) return;
    _sorts.clear();
    _scheduleView(immediate: true);
  }

  // ---------------------------------------------------------------- filters

  void addFilter(FilterRule rule) {
    _filters.add(rule);
    _scheduleView(immediate: true);
  }

  void updateFilter(int index, FilterRule rule) {
    if (index < 0 || index >= _filters.length) return;
    _filters[index] = rule;
    _scheduleView(immediate: true);
  }

  void removeFilter(int index) {
    if (index < 0 || index >= _filters.length) return;
    _filters.removeAt(index);
    _scheduleView(immediate: true);
  }

  void toggleFilterEnabled(int index) {
    if (index < 0 || index >= _filters.length) return;
    _filters[index] = _filters[index].copyWith(enabled: !_filters[index].enabled);
    _scheduleView(immediate: true);
  }

  void clearFilters() {
    if (_filters.isEmpty && _quickSearch.isEmpty) return;
    _filters.clear();
    _quickSearch = '';
    _scheduleView(immediate: true);
  }

  // ------------------------------------------------------------- pipeline

  /// Recomputing a view over a huge file is a full pass over the disk, so
  /// typing in the search box is debounced; explicit actions run at once.
  void _scheduleView({bool immediate = false}) {
    _viewDebounce?.cancel();
    final delay = immediate
        ? Duration.zero
        : Duration(milliseconds: isStreaming ? 500 : 60);
    if (delay == Duration.zero) {
      unawaited(_applyView());
    } else {
      _viewDebounce = Timer(delay, () => unawaited(_applyView()));
    }
    notifyListeners();
  }

  Future<void> applyViewNow() => _applyView();

  Future<void> _applyView() async {
    final source = _source;
    if (source == null) return;
    final generation = ++_viewGeneration;
    _busy = true;
    _busyProgress = 0;
    notifyListeners();
    try {
      final result = await source.applyView(
        _filters,
        _quickSearch,
        _sorts,
        onProgress: (value) {
          if (generation != _viewGeneration) return;
          _busyProgress = value;
          notifyListeners();
        },
      );
      if (generation != _viewGeneration || result.cancelled) return;
      if (!result.sortApplied && _sorts.isNotEmpty) {
        _sorts.clear();
        _notice = 'Ordenação disponível para até ${_formatCount(source.sortLimit)} registros. '
            'Filtre antes de ordenar.';
      }
    } catch (e) {
      if (generation == _viewGeneration) _error = 'Falha ao aplicar filtros: $e';
    } finally {
      if (generation == _viewGeneration) {
        _busy = false;
        if (_selectedRowIndex != null && _selectedRowIndex! >= visibleRowCount) {
          _selectedRowIndex = visibleRowCount == 0 ? null : visibleRowCount - 1;
          _selectedRow = null;
        }
        if (_selectedRowIndex != null) unawaited(_loadSelected(_selectedRowIndex!));
        notifyListeners();
      }
    }
  }

  static String _formatCount(int value) {
    final text = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) buffer.write('.');
      buffer.write(text[i]);
    }
    return buffer.toString();
  }

  // ------------------------------------------------------------------ export

  Future<int> export(String path, {bool onlyVisibleColumns = true}) {
    final source = _source!;
    final columnIndices =
        onlyVisibleColumns ? visibleColumns : List<int>.generate(source.columnCount, (i) => i);
    return source.exportTo(path, columnIndices);
  }

  /// Distinct values for the value-picker filter.
  Future<List<String>> distinctValues(int column) =>
      _source?.distinctValues(column) ?? Future.value(const <String>[]);

  @override
  void dispose() {
    _viewDebounce?.cancel();
    _source?.removeListener(_onSourceChanged);
    _source?.dispose();
    super.dispose();
  }
}
