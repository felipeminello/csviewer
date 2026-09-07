import 'dart:typed_data';

/// Rows per indexed block. The index stores one file offset per block, so a
/// 50-million-row file costs ~200k offsets (a couple of MB) instead of holding
/// the records themselves.
const int kBlockRows = 256;

const int _quote = 34;
const int _cr = 13;
const int _lf = 10;

/// Streaming scanner that finds record boundaries in raw CSV bytes.
///
/// It is fed the file in chunks and keeps all the state it needs (inside
/// quotes, pending CR, current row start) between calls, so a file of any size
/// can be indexed with a fixed amount of memory. The rules mirror
/// [parseCsvString] exactly — quotes only open at the start of a field, `""` is
/// an escape, blank lines are skipped — otherwise block offsets and parsed
/// records would drift apart.
class CsvIndexer {
  CsvIndexer({
    required String delimiter,
    this.headerRows = 1,
    this.blockRows = kBlockRows,
  }) : _delimiter = delimiter.codeUnitAt(0) {
    _special = Uint8List(256);
    _special[_quote] = 1;
    _special[_cr] = 1;
    _special[_lf] = 1;
    _special[_delimiter] = 1;
  }

  final int _delimiter;
  final int headerRows;
  final int blockRows;
  late final Uint8List _special;

  /// File offset of the first row of each block.
  final List<int> blockOffsets = <int>[];

  int dataRows = 0;
  int headerBytes = 0;
  int _headerRowsSeen = 0;

  int _base = 0; // absolute offset of the current chunk's first byte
  int _rowStart = 0;
  int _crEnd = 0;
  bool _inQuotes = false;
  bool _justClosedQuote = false;
  bool _pendingLf = false;
  bool _atFieldStart = true;
  bool _rowHasContent = false;

  /// Offset just past the last complete record; block reads must not go beyond.
  int get endOfCountedData => _rowStart;

  void feed(Uint8List chunk) {
    final n = chunk.length;
    var i = 0;
    while (i < n) {
      if (_inQuotes) {
        while (i < n && chunk[i] != _quote) {
          i++;
        }
        if (i >= n) break;
        _inQuotes = false;
        _justClosedQuote = true;
        _rowHasContent = true;
        i++;
        continue;
      }
      if (_justClosedQuote) {
        _justClosedQuote = false;
        if (chunk[i] == _quote) {
          _inQuotes = true;
          i++;
          continue;
        }
      }
      if (_pendingLf) {
        _pendingLf = false;
        if (chunk[i] == _lf) {
          i++;
          _endRow(_base + i);
          continue;
        }
        _endRow(_crEnd);
      }
      final start = i;
      while (i < n && _special[chunk[i]] == 0) {
        i++;
      }
      if (i > start) {
        _rowHasContent = true;
        _atFieldStart = false;
      }
      if (i >= n) break;
      final b = chunk[i];
      if (b == _delimiter) {
        _rowHasContent = true;
        _atFieldStart = true;
        i++;
      } else if (b == _quote) {
        _rowHasContent = true;
        if (_atFieldStart) {
          _inQuotes = true;
          _atFieldStart = false;
        }
        i++;
      } else if (b == _lf) {
        i++;
        _endRow(_base + i);
      } else {
        // CR: the row ends here, but a following LF belongs to this break.
        i++;
        _crEnd = _base + i;
        _pendingLf = true;
      }
    }
    _base += n;
  }

  /// Closes the last record. [fileLength] is the total size in bytes.
  void finish(int fileLength) {
    if (_pendingLf) {
      _pendingLf = false;
      _endRow(_crEnd);
      return;
    }
    if (_rowHasContent) _endRow(fileLength);
  }

  void _endRow(int nextStart) {
    if (_rowHasContent) {
      if (_headerRowsSeen < headerRows) {
        _headerRowsSeen++;
        headerBytes = nextStart;
      } else {
        if (dataRows % blockRows == 0) blockOffsets.add(_rowStart);
        dataRows++;
      }
    }
    _rowStart = nextStart;
    _rowHasContent = false;
    _atFieldStart = true;
  }
}

/// Byte range of a run of blocks, used to read many records with one seek.
class BlockRange {
  const BlockRange(this.firstBlock, this.start, this.end);
  final int firstBlock;
  final int start;
  final int end;
  int get length => end - start;
}

/// Resolves block numbers to byte ranges against a (possibly partial) index.
class CsvBlockMap {
  CsvBlockMap(this.offsets, this.endOffset, {this.blockRows = kBlockRows});

  final List<int> offsets;
  final int endOffset;
  final int blockRows;

  int get blockCount => offsets.length;

  BlockRange range(int firstBlock, int blockCount) {
    final last = firstBlock + blockCount;
    final end = last < offsets.length ? offsets[last] : endOffset;
    return BlockRange(firstBlock, offsets[firstBlock], end);
  }
}
