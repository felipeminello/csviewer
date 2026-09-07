import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../model/column_meta.dart';
import '../model/csv_table.dart';
import '../model/filter.dart';
import '../model/sort_spec.dart';
import 'csv_byte_records.dart';
import 'csv_index.dart';
import 'csv_parser.dart';
import 'csv_writer.dart';

/// Ordering a view materialises one key per row, so it is allowed only while
/// the view fits comfortably in memory. Above this, the user is asked to
/// filter first.
const int kMaxSortableRows = 2000000;

const int _readChunkBytes = 4 * 1024 * 1024;
const int _blocksPerRead = 64; // ~16k records per read while scanning

/// Rows returned for a slice of the current view.
class RowWindow {
  const RowWindow(this.start, this.rows, this.sourceRows);
  final int start;
  final List<List<String>> rows;
  final List<int> sourceRows;
}

class OpenResult {
  const OpenResult({
    required this.columns,
    required this.delimiter,
    required this.encodingName,
    required this.fileSize,
    required this.warnings,
  });

  final List<ColumnMeta> columns;
  final String delimiter;
  final String encodingName;
  final int fileSize;
  final List<String> warnings;
}

class ViewResult {
  const ViewResult({
    required this.rowCount,
    this.sortApplied = true,
    this.cancelled = false,
  });

  final int rowCount;
  final bool sortApplied;
  final bool cancelled;
}

class IndexProgress {
  const IndexProgress(this.rows, this.bytesRead, this.totalBytes, this.done);
  final int rows;
  final int bytesRead;
  final int totalBytes;
  final bool done;
}

/// Main-isolate handle to the background worker that owns the file.
class CsvWorkerClient {
  CsvWorkerClient._(this._commands, this._responses);

  final SendPort _commands;
  final ReceivePort _responses;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  final Map<int, void Function(double)> _progress = <int, void Function(double)>{};
  int _nextId = 1;

  void Function(IndexProgress)? onIndexProgress;

  static Future<CsvWorkerClient> spawn() async {
    final responses = ReceivePort();
    await Isolate.spawn(_workerMain, responses.sendPort, debugName: 'csviewer-io');
    final stream = responses.asBroadcastStream();
    final commands = await stream.first as SendPort;
    final client = CsvWorkerClient._(commands, responses);
    stream.listen(client._handleMessage);
    return client;
  }

  void _handleMessage(dynamic message) {
    if (message is! Map) return;
    final event = message['event'];
    if (event == 'index') {
      onIndexProgress?.call(IndexProgress(
        message['rows'] as int,
        message['bytes'] as int,
        message['total'] as int,
        message['done'] as bool,
      ));
      return;
    }
    final id = message['id'] as int?;
    if (id == null) return;
    if (message.containsKey('progress')) {
      _progress[id]?.call(message['progress'] as double);
      return;
    }
    final completer = _pending.remove(id);
    _progress.remove(id);
    if (completer == null) return;
    if (message.containsKey('error')) {
      completer.completeError(StateError(message['error'] as String));
    } else {
      completer.complete(message['ok']);
    }
  }

  Future<Object?> _send(String cmd, Map<String, Object?> args, {void Function(double)? onProgress}) {
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    if (onProgress != null) _progress[id] = onProgress;
    _commands.send(<String, Object?>{'id': id, 'cmd': cmd, ...args});
    return completer.future;
  }

  Future<OpenResult> open(
    String path, {
    String? delimiter,
    required String encoding,
    required bool hasHeader,
    int sortLimit = kMaxSortableRows,
  }) async {
    final result = await _send('open', {
      'path': path,
      'delimiter': delimiter,
      'encoding': encoding,
      'hasHeader': hasHeader,
      'sortLimit': sortLimit,
    }) as Map;
    return OpenResult(
      columns: (result['columns'] as List).cast<ColumnMeta>(),
      delimiter: result['delimiter'] as String,
      encodingName: result['encodingName'] as String,
      fileSize: result['fileSize'] as int,
      warnings: (result['warnings'] as List).cast<String>(),
    );
  }

  Future<RowWindow> window(int start, int count) async {
    final result = await _send('window', {'start': start, 'count': count}) as Map;
    return RowWindow(
      start,
      (result['rows'] as List).map((r) => (r as List).cast<String>()).toList(),
      (result['sourceRows'] as List).cast<int>(),
    );
  }

  Future<ViewResult> applyView({
    required List<FilterRule> filters,
    required String search,
    required List<SortSpec> sorts,
    void Function(double)? onProgress,
  }) async {
    final result = await _send('view', {
      'filters': filters,
      'search': search,
      'sorts': sorts,
    }, onProgress: onProgress) as Map;
    return ViewResult(
      rowCount: result['rowCount'] as int,
      sortApplied: result['sortApplied'] as bool,
      cancelled: result['cancelled'] as bool,
    );
  }

  Future<List<String>> distinctValues(int column, int limit, {void Function(double)? onProgress}) async {
    final result = await _send('distinct', {'column': column, 'limit': limit}, onProgress: onProgress) as Map;
    return (result['values'] as List).cast<String>();
  }

  Future<int> export(String path, List<int> columns, {void Function(double)? onProgress}) async {
    final result = await _send('export', {'path': path, 'columns': columns}, onProgress: onProgress) as Map;
    return result['rows'] as int;
  }

  void dispose() {
    _commands.send(<String, Object?>{'cmd': 'close'});
    _responses.close();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(StateError('worker encerrado'));
    }
    _pending.clear();
  }
}

// ---------------------------------------------------------------- worker side

void _workerMain(SendPort responses) {
  final commands = ReceivePort();
  responses.send(commands.sendPort);
  final session = _Session(responses);
  commands.listen((dynamic message) async {
    final map = (message as Map).cast<String, Object?>();
    final cmd = map['cmd'] as String;
    if (cmd == 'close') {
      await session.close();
      commands.close();
      return;
    }
    final id = map['id'] as int;
    try {
      final result = await session.handle(cmd, map, id);
      responses.send(<String, Object?>{'id': id, 'ok': result});
    } catch (e) {
      responses.send(<String, Object?>{'id': id, 'error': '$e'});
    }
  });
}

class _Session {
  _Session(this._responses);

  final SendPort _responses;

  String _path = '';
  String _delimiter = ',';
  String _encoding = encodingAuto;
  String _encodingName = 'UTF-8';
  bool _hasHeader = true;
  int _sortLimit = kMaxSortableRows;
  int _fileSize = 0;
  List<ColumnMeta> _columns = const <ColumnMeta>[];

  final List<int> _blockOffsets = <int>[];
  int _endOfData = 0;
  int _totalRows = 0;
  final Completer<void> _indexed = Completer<void>();

  Uint32List? _view; // null = every row, in file order
  int _viewCount = 0;
  int _scanGeneration = 0;

  RandomAccessFile? _windowRaf;
  RandomAccessFile? _scanRaf;
  RandomAccessFile? _indexRaf;

  bool _closing = false;
  Future<void> _queue = Future<void>.value();
  final Map<int, Uint8List> _blockCache = <int, Uint8List>{};
  bool _viewOrdered = true; // view indices ascending (no sort applied)

  Future<Object?> handle(String cmd, Map<String, Object?> args, int id) async {
    switch (cmd) {
      case 'open':
        return _open(args);
      case 'window':
        return _serialize(() => _window(args['start'] as int, args['count'] as int));
      case 'view':
        return _view_(args, id);
      case 'distinct':
        return _serialize(() => _distinct(args['column'] as int, args['limit'] as int, id));
      case 'export':
        return _serialize(() => _export(args['path'] as String, (args['columns'] as List).cast<int>(), id));
    }
    throw StateError('comando desconhecido: $cmd');
  }

  /// Serialises work that shares a file handle.
  Future<T> _serialize<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await task());
      } catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  Future<Map<String, Object?>> _open(Map<String, Object?> args) async {
    _path = args['path'] as String;
    _encoding = args['encoding'] as String? ?? encodingAuto;
    _hasHeader = args['hasHeader'] as bool? ?? true;
    _sortLimit = args['sortLimit'] as int? ?? kMaxSortableRows;
    final file = File(_path);
    _fileSize = await file.length();

    // The head of the file is enough to settle encoding, delimiter and types.
    _indexRaf = await file.open();
    final headBytes = await _indexRaf!.read(_fileSize < 1024 * 1024 ? _fileSize : 1024 * 1024);
    final decodedHead = decodeBytes(headBytes, encoding: _encoding);
    _encodingName = decodedHead.encodingName;
    _delimiter = args['delimiter'] as String? ?? detectDelimiter(decodedHead.text);

    final headRows = parseCsvString(decodedHead.text, _delimiter, maxRows: 501);
    final warnings = <String>[];
    List<String> names;
    List<List<String>> sample;
    if (_hasHeader) {
      names = headRows.isEmpty ? <String>[] : headRows.first.map((e) => e.trim()).toList();
      sample = headRows.length > 1 ? headRows.sublist(1) : <List<String>>[];
    } else {
      names = <String>[];
      sample = headRows;
    }
    var widest = names.length;
    for (final row in sample) {
      if (row.length > widest) widest = row.length;
    }
    names = normaliseHeaders(names, widest);
    _columns = inferColumns(names, sample);

    unawaited(_runIndex());
    return <String, Object?>{
      'columns': _columns,
      'delimiter': _delimiter,
      'encodingName': _encodingName,
      'fileSize': _fileSize,
      'warnings': warnings,
    };
  }

  /// One sequential pass that records where each block of records starts.
  Future<void> _runIndex() async {
    final indexer = CsvIndexer(delimiter: _delimiter, headerRows: _hasHeader ? 1 : 0);
    final raf = _indexRaf!;
    await raf.setPosition(0);
    var position = 0;
    var lastReport = 0;
    try {
      while (position < _fileSize && !_closing) {
        final want = _fileSize - position < _readChunkBytes ? _fileSize - position : _readChunkBytes;
        final chunk = await raf.read(want);
        if (chunk.isEmpty) break;
        indexer.feed(chunk);
        position += chunk.length;
        _publishIndex(indexer);
        if (position - lastReport >= _readChunkBytes) {
          lastReport = position;
          _responses.send(<String, Object?>{
            'event': 'index',
            'rows': _totalRows,
            'bytes': position,
            'total': _fileSize,
            'done': false,
          });
        }
      }
      indexer.finish(_fileSize);
      _publishIndex(indexer);
    } finally {
      if (!_indexed.isCompleted) _indexed.complete();
      _responses.send(<String, Object?>{
        'event': 'index',
        'rows': _totalRows,
        'bytes': _fileSize,
        'total': _fileSize,
        'done': true,
      });
    }
  }

  void _publishIndex(CsvIndexer indexer) {
    for (var i = _blockOffsets.length; i < indexer.blockOffsets.length; i++) {
      _blockOffsets.add(indexer.blockOffsets[i]);
    }
    _endOfData = indexer.endOfCountedData;
    _totalRows = indexer.dataRows;
    if (_view == null) _viewCount = _totalRows;
  }

  bool get _isLatin1 => _encodingName.startsWith('Latin');

  /// Raw bytes covering [count] blocks — the scans read records straight from
  /// these without decoding fields they never look at.
  Future<Uint8List> _readBlockBytes(RandomAccessFile raf, int firstBlock, int count) async {
    final last = firstBlock + count;
    final start = _blockOffsets[firstBlock];
    final end = last < _blockOffsets.length ? _blockOffsets[last] : _endOfData;
    if (end <= start) return Uint8List(0);
    await raf.setPosition(start);
    return raf.read(end - start);
  }

  Future<Uint8List> _blockBytes(RandomAccessFile raf, int block) async {
    final cached = _blockCache[block];
    if (cached != null) return cached;
    final bytes = await _readBlockBytes(raf, block, 1);
    if (_blockCache.length > 32) _blockCache.remove(_blockCache.keys.first);
    _blockCache[block] = bytes;
    return bytes;
  }

  /// Rows for a slice of the view. Requests are grouped by block so a sorted
  /// view — where consecutive rows live far apart in the file — still reads
  /// each block at most once, and only the wanted records are decoded.
  Future<Map<String, Object?>> _window(int start, int count) async {
    final raf = _windowRaf ??= await File(_path).open();
    final view = _view;
    final sourceRows = <int>[];
    for (var i = 0; i < count; i++) {
      final position = start + i;
      if (position >= _viewCount) break;
      final rowIndex = view == null ? position : view[position];
      if (rowIndex >= _totalRows) break;
      sourceRows.add(rowIndex);
    }

    final byBlock = <int, List<int>>{};
    for (var i = 0; i < sourceRows.length; i++) {
      byBlock.putIfAbsent(sourceRows[i] ~/ kBlockRows, () => <int>[]).add(i);
    }
    final rows = List<List<String>?>.filled(sourceRows.length, null);
    final blocks = byBlock.keys.toList()..sort();
    for (final block in blocks) {
      if (block >= _blockOffsets.length) continue;
      final wanted = byBlock[block]!..sort((a, b) => sourceRows[a].compareTo(sourceRows[b]));
      final records = CsvByteRecords(await _blockBytes(raf, block), _delimiter, latin1: _isLatin1);
      var offset = 0;
      var next = 0;
      while (next < wanted.length && records.moveNext()) {
        if (offset == sourceRows[wanted[next]] % kBlockRows) {
          rows[wanted[next]] = records.current.materialise();
          next++;
        }
        offset++;
      }
    }
    return <String, Object?>{
      'rows': <List<String>>[for (final row in rows) row ?? const <String>[]],
      'sourceRows': sourceRows,
    };
  }

  Future<Map<String, Object?>> _view_(Map<String, Object?> args, int id) async {
    final generation = ++_scanGeneration;
    final filters = (args['filters'] as List).cast<FilterRule>();
    final search = (args['search'] as String).toLowerCase();
    final sorts = (args['sorts'] as List).cast<SortSpec>();
    return _serialize(() => _scan(generation, filters, search, sorts, id));
  }

  Future<Map<String, Object?>> _scan(
    int generation,
    List<FilterRule> filters,
    String search,
    List<SortSpec> sorts,
    int id,
  ) async {
    await _indexed.future;
    if (generation != _scanGeneration) {
      return <String, Object?>{'rowCount': _viewCount, 'sortApplied': true, 'cancelled': true};
    }

    final program = FilterProgram.compile(filters, _columns);
    final filtering = !program.isEmpty || search.isNotEmpty;
    if (!filtering && sorts.isEmpty) {
      _view = null;
      _viewCount = _totalRows;
      _viewOrdered = true;
      _blockCache.clear();
      return <String, Object?>{'rowCount': _totalRows, 'sortApplied': true, 'cancelled': false};
    }

    final raf = _scanRaf ??= await File(_path).open();
    // Without filters the matching rows are simply 0..n-1, so nothing is
    // materialised — only a sort needs the keys.
    final matches = filtering ? _Uint32Builder() : null;
    final keyColumns = sorts.map((s) => _columns[s.column]).toList();
    final keys = List<List<Object?>>.generate(sorts.length, (_) => <Object?>[]);
    var sortApplied = sorts.isNotEmpty;
    var kept = 0;
    final blockCount = _blockOffsets.length;

    for (var block = 0; block < blockCount; block += _blocksPerRead) {
      if (generation != _scanGeneration || _closing) {
        return <String, Object?>{'rowCount': _viewCount, 'sortApplied': true, 'cancelled': true};
      }
      final take = block + _blocksPerRead <= blockCount ? _blocksPerRead : blockCount - block;
      final bytes = await _readBlockBytes(raf, block, take);
      final records = CsvByteRecords(bytes, _delimiter, latin1: _isLatin1);
      var rowIndex = block * kBlockRows;
      while (records.moveNext()) {
        if (rowIndex >= _totalRows) break;
        final row = records.current;
        final keep = !filtering ||
            (program.matches(row) && (search.isEmpty || _rowContains(row, search)));
        if (keep) {
          matches?.add(rowIndex);
          kept++;
          if (sortApplied) {
            if (kept > _sortLimit) {
              sortApplied = false;
              for (final list in keys) {
                list.clear();
              }
            } else {
              for (var s = 0; s < sorts.length; s++) {
                keys[s].add(sortKeyOf(row, sorts[s].column, keyColumns[s]));
              }
            }
          }
        }
        rowIndex++;
      }
      _responses.send(<String, Object?>{'id': id, 'progress': (block + take) / blockCount});
    }

    final indices = matches?.toList();
    if (sortApplied && sorts.isNotEmpty) {
      final order = List<int>.generate(kept, (i) => i);
      order.sort((a, b) {
        for (var s = 0; s < sorts.length; s++) {
          final comparison = compareSortKeys(keys[s][a], keys[s][b]);
          if (comparison != 0) return sorts[s].ascending ? comparison : -comparison;
        }
        return a.compareTo(b); // stable: keep file order on ties
      });
      final sorted = Uint32List(kept);
      for (var i = 0; i < order.length; i++) {
        sorted[i] = indices == null ? order[i] : indices[order[i]];
      }
      _view = sorted;
    } else {
      _view = indices;
    }
    _viewCount = _view?.length ?? _totalRows;
    _viewOrdered = !(sortApplied && sorts.isNotEmpty);
    _blockCache.clear();
    return <String, Object?>{
      'rowCount': _viewCount,
      'sortApplied': sortApplied,
      'cancelled': false,
    };
  }

  bool _rowContains(List<String> row, String needle) {
    for (final cell in row) {
      if (cell.toLowerCase().contains(needle)) return true;
    }
    return false;
  }

  Future<Map<String, Object?>> _distinct(int column, int limit, int id) async {
    await _indexed.future;
    final raf = _scanRaf ??= await File(_path).open();
    final values = <String>{};
    final blockCount = _blockOffsets.length;
    for (var block = 0; block < blockCount; block += _blocksPerRead) {
      final take = block + _blocksPerRead <= blockCount ? _blocksPerRead : blockCount - block;
      final bytes = await _readBlockBytes(raf, block, take);
      final records = CsvByteRecords(bytes, _delimiter, latin1: _isLatin1);
      while (records.moveNext()) {
        final row = records.current;
        values.add(column < row.length ? row[column] : '');
        if (values.length >= limit) break;
      }
      _responses.send(<String, Object?>{'id': id, 'progress': (block + take) / blockCount});
      if (values.length >= limit) break;
    }
    final list = values.toList();
    final meta = _columns[column];
    list.sort((a, b) => compareValues(a, b, meta));
    return <String, Object?>{'values': list};
  }

  /// Writes the current view to [path] without ever holding it in memory.
  ///
  /// While the view is in file order — no sort, or filters only — this is a
  /// single sequential pass over the file. A sorted view is written page by
  /// page, reading each page's records in file order.
  Future<Map<String, Object?>> _export(String path, List<int> columns, int id) async {
    await _indexed.future;
    final sink = File(path).openWrite();
    var written = 0;
    try {
      sink.write(encodeHeader(_columns, columns, _delimiter));
      if (_viewOrdered) {
        final raf = _scanRaf ??= await File(_path).open();
        final view = _view;
        final blockCount = _blockOffsets.length;
        var viewPointer = 0;
        for (var block = 0; block < blockCount; block += _blocksPerRead) {
          final take = block + _blocksPerRead <= blockCount ? _blocksPerRead : blockCount - block;
          final records = CsvByteRecords(
            await _readBlockBytes(raf, block, take),
            _delimiter,
            latin1: _isLatin1,
          );
          var rowIndex = block * kBlockRows;
          final buffer = StringBuffer();
          while (records.moveNext()) {
            if (rowIndex >= _totalRows) break;
            var include = true;
            if (view != null) {
              while (viewPointer < view.length && view[viewPointer] < rowIndex) {
                viewPointer++;
              }
              include = viewPointer < view.length && view[viewPointer] == rowIndex;
              if (include) viewPointer++;
            }
            if (include) {
              buffer.writeln(_line(records.current, columns));
              written++;
            }
            rowIndex++;
          }
          sink.write(buffer.toString());
          _responses.send(<String, Object?>{
            'id': id,
            'progress': blockCount == 0 ? 1.0 : (block + take) / blockCount,
          });
        }
      } else {
        const pageSize = 4096;
        for (var start = 0; start < _viewCount; start += pageSize) {
          final page = await _window(start, pageSize);
          final rows = (page['rows'] as List).cast<List<String>>();
          final buffer = StringBuffer();
          for (final row in rows) {
            buffer.writeln(_line(row, columns));
            written++;
          }
          sink.write(buffer.toString());
          _responses.send(<String, Object?>{
            'id': id,
            'progress': _viewCount == 0 ? 1.0 : (start + rows.length) / _viewCount,
          });
        }
      }
    } finally {
      await sink.flush();
      await sink.close();
    }
    return <String, Object?>{'rows': written};
  }

  String _line(List<String> row, List<int> columns) => columns
      .map((c) => escapeCsvField(c < row.length ? row[c] : '', _delimiter))
      .join(_delimiter);

  /// Stops any pass in flight and releases the file handles. Closing a
  /// document must not leave a multi-gigabyte scan running.
  Future<void> close() async {
    _closing = true;
    await _windowRaf?.close();
    await _scanRaf?.close();
    await _indexRaf?.close();
  }
}

/// Grows by doubling into typed memory: 4 bytes per matching row instead of
/// the 8+ a growable `List<int>` would use.
class _Uint32Builder {
  Uint32List _data = Uint32List(1024);
  int _length = 0;

  int get length => _length;

  void add(int value) {
    if (_length == _data.length) {
      final grown = Uint32List(_data.length * 2);
      grown.setRange(0, _length, _data);
      _data = grown;
    }
    _data[_length++] = value;
  }

  Uint32List toList() => Uint32List.sublistView(_data, 0, _length);
}
