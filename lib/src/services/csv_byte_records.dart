import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

const int _quote = 34;
const int _cr = 13;
const int _lf = 10;

/// Iterates CSV records straight over raw bytes, recording where each field
/// starts and ends but decoding none of them.
///
/// Scanning a filter over a multi-gigabyte file spends almost all of its time
/// building strings that are never looked at: a row has a dozen fields and a
/// filter usually reads one. Here the row is a lazy list, so only the fields a
/// filter (or a sort key) actually touches become strings.
///
/// The rules match [parseCsvString] exactly, including blank-line skipping and
/// stray characters after a closing quote.
class CsvByteRecords {
  CsvByteRecords(this._bytes, String delimiter, {bool latin1 = false})
      : _delimiter = delimiter.codeUnitAt(0),
        _row = LazyByteRow._(_bytes, latin1);

  final Uint8List _bytes;
  final int _delimiter;
  final LazyByteRow _row;
  int _pos = 0;

  LazyByteRow get current => _row;

  bool moveNext() {
    final bytes = _bytes;
    final n = bytes.length;
    while (true) {
      if (_pos >= n) return false;
      _row._count = 0;
      while (true) {
        int start;
        int end;
        var escapes = false;
        if (_pos < n && bytes[_pos] == _quote) {
          _pos++;
          start = _pos;
          while (_pos < n) {
            if (bytes[_pos] == _quote) {
              if (_pos + 1 < n && bytes[_pos + 1] == _quote) {
                escapes = true;
                _pos += 2;
                continue;
              }
              break;
            }
            _pos++;
          }
          end = _pos;
          if (_pos < n) _pos++; // closing quote
          while (_pos < n &&
              bytes[_pos] != _delimiter &&
              bytes[_pos] != _cr &&
              bytes[_pos] != _lf) {
            _pos++;
          }
        } else {
          start = _pos;
          while (_pos < n &&
              bytes[_pos] != _delimiter &&
              bytes[_pos] != _cr &&
              bytes[_pos] != _lf) {
            _pos++;
          }
          end = _pos;
        }
        _row._add(start, end, escapes);
        if (_pos >= n) break;
        final c = bytes[_pos];
        if (c == _delimiter) {
          _pos++;
          continue;
        }
        if (c == _cr && _pos + 1 < n && bytes[_pos + 1] == _lf) {
          _pos += 2;
        } else {
          _pos++;
        }
        break;
      }
      // A blank line is a single empty field; skip it, like the parser does.
      if (_row._count == 1 && _row._ends[0] == _row._starts[0]) continue;
      return true;
    }
  }
}

/// A record whose fields are decoded only when read.
class LazyByteRow extends ListBase<String> {
  LazyByteRow._(this._bytes, this._latin1);

  final Uint8List _bytes;
  final bool _latin1;
  Int32List _starts = Int32List(16);
  Int32List _ends = Int32List(16);
  Uint8List _escaped = Uint8List(16);
  int _count = 0;

  void _add(int start, int end, bool escapes) {
    if (_count == _starts.length) {
      _starts = Int32List(_count * 2)..setRange(0, _count, _starts);
      _ends = Int32List(_count * 2)..setRange(0, _count, _ends);
      _escaped = Uint8List(_count * 2)..setRange(0, _count, _escaped);
    }
    _starts[_count] = start;
    _ends[_count] = end;
    _escaped[_count] = escapes ? 1 : 0;
    _count++;
  }

  @override
  int get length => _count;

  @override
  set length(int value) => throw UnsupportedError('registro somente leitura');

  @override
  String operator [](int index) {
    final start = _starts[index];
    final end = _ends[index];
    if (end <= start) return '';
    final view = Uint8List.sublistView(_bytes, start, end);
    final text = _latin1 ? latin1.decode(view, allowInvalid: true) : utf8.decode(view, allowMalformed: true);
    return _escaped[index] == 1 ? text.replaceAll('""', '"') : text;
  }

  @override
  void operator []=(int index, String value) =>
      throw UnsupportedError('registro somente leitura');

  /// Copy of the record as plain strings.
  List<String> materialise() => List<String>.generate(_count, (i) => this[i]);
}
