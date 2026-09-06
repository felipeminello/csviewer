import 'dart:convert';
import 'dart:typed_data';

import '../model/column_meta.dart';

const int _quote = 34; // "
const int _cr = 13;
const int _lf = 10;

const List<String> supportedDelimiters = <String>[',', ';', '\t', '|'];

String delimiterLabel(String delimiter) {
  switch (delimiter) {
    case ',':
      return 'Vírgula (,)';
    case ';':
      return 'Ponto e vírgula (;)';
    case '\t':
      return 'Tabulação';
    case '|':
      return 'Barra vertical (|)';
    default:
      return delimiter;
  }
}

class DecodedText {
  const DecodedText(this.text, this.encodingName);
  final String text;
  final String encodingName;
}

const String encodingAuto = 'Automático';
const List<String> supportedEncodings = <String>[encodingAuto, 'UTF-8', 'Latin-1 (ISO-8859-1)', 'UTF-16'];

/// Decodes raw file bytes, honouring the BOM when present and falling back to
/// Latin-1 when the bytes are not valid UTF-8.
DecodedText decodeBytes(Uint8List bytes, {String encoding = encodingAuto}) {
  if (encoding == 'UTF-8') {
    return DecodedText(utf8.decode(_stripUtf8Bom(bytes), allowMalformed: true), 'UTF-8');
  }
  if (encoding == 'Latin-1 (ISO-8859-1)') {
    return DecodedText(latin1.decode(bytes, allowInvalid: true), 'Latin-1');
  }
  if (encoding == 'UTF-16') {
    return DecodedText(_decodeUtf16(bytes, littleEndian: true), 'UTF-16');
  }

  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return DecodedText(utf8.decode(bytes.sublist(3), allowMalformed: true), 'UTF-8 (BOM)');
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return DecodedText(_decodeUtf16(bytes.sublist(2), littleEndian: true), 'UTF-16 LE');
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return DecodedText(_decodeUtf16(bytes.sublist(2), littleEndian: false), 'UTF-16 BE');
  }
  try {
    return DecodedText(const Utf8Decoder(allowMalformed: false).convert(bytes), 'UTF-8');
  } on FormatException {
    return DecodedText(latin1.decode(bytes, allowInvalid: true), 'Latin-1');
  }
}

Uint8List _stripUtf8Bom(Uint8List bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return bytes.sublist(3);
  }
  return bytes;
}

String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
  final units = <int>[];
  for (var i = 0; i + 1 < bytes.length; i += 2) {
    units.add(littleEndian ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1]);
  }
  return String.fromCharCodes(units);
}

/// Picks the delimiter that yields the most consistent number of fields
/// across the first lines of the file.
String detectDelimiter(String text) {
  final sample = text.length > 64 * 1024 ? text.substring(0, 64 * 1024) : text;
  var best = ',';
  var bestScore = -1.0;
  for (final candidate in supportedDelimiters) {
    final rows = parseCsvString(sample, candidate, maxRows: 25);
    if (rows.isEmpty) continue;
    final counts = <int, int>{};
    for (final row in rows) {
      counts[row.length] = (counts[row.length] ?? 0) + 1;
    }
    var modeLength = 1;
    var modeCount = 0;
    counts.forEach((length, count) {
      if (count > modeCount || (count == modeCount && length > modeLength)) {
        modeLength = length;
        modeCount = count;
      }
    });
    if (modeLength < 2) continue;
    final consistency = modeCount / rows.length;
    final score = consistency * consistency * modeLength;
    if (score > bestScore) {
      bestScore = score;
      best = candidate;
    }
  }
  return best;
}

/// RFC 4180 parser: honours quoted fields, `""` escapes, embedded newlines and
/// CR / LF / CRLF line endings. Blank lines are skipped.
List<List<String>> parseCsvString(String text, String delimiter, {int? maxRows}) {
  final rows = <List<String>>[];
  final n = text.length;
  final d = delimiter.codeUnitAt(0);
  var i = 0;
  while (i < n) {
    final row = <String>[];
    var endOfRow = false;
    while (!endOfRow) {
      String value;
      if (i < n && text.codeUnitAt(i) == _quote) {
        i++;
        final buffer = StringBuffer();
        var segmentStart = i;
        var closed = false;
        while (i < n) {
          if (text.codeUnitAt(i) == _quote) {
            if (i + 1 < n && text.codeUnitAt(i + 1) == _quote) {
              buffer.write(text.substring(segmentStart, i + 1));
              i += 2;
              segmentStart = i;
              continue;
            }
            buffer.write(text.substring(segmentStart, i));
            i++;
            closed = true;
            break;
          }
          i++;
        }
        if (!closed) {
          buffer.write(text.substring(segmentStart, n));
          i = n;
        }
        value = buffer.toString();
        // Ignore stray characters between a closing quote and the next
        // delimiter, which some exporters emit.
        while (i < n) {
          final c = text.codeUnitAt(i);
          if (c == d || c == _cr || c == _lf) break;
          i++;
        }
      } else {
        final start = i;
        while (i < n) {
          final c = text.codeUnitAt(i);
          if (c == d || c == _cr || c == _lf) break;
          i++;
        }
        value = text.substring(start, i);
      }
      row.add(value);
      if (i >= n) {
        endOfRow = true;
      } else {
        final c = text.codeUnitAt(i);
        if (c == d) {
          i++;
        } else {
          if (c == _cr && i + 1 < n && text.codeUnitAt(i + 1) == _lf) {
            i += 2;
          } else {
            i++;
          }
          endOfRow = true;
        }
      }
    }
    if (row.length == 1 && row.first.isEmpty) continue;
    rows.add(row);
    if (maxRows != null && rows.length >= maxRows) break;
  }
  return rows;
}

/// Infers a type per column from a sample of its values, so that sorting and
/// range filters behave like a spreadsheet rather than like plain text.
List<ColumnMeta> inferColumns(List<String> names, List<List<String>> rows, {int sampleSize = 500}) {
  final metas = <ColumnMeta>[];
  final limit = rows.length < sampleSize ? rows.length : sampleSize;
  for (var c = 0; c < names.length; c++) {
    var seen = 0;
    var dotNumbers = 0;
    var commaNumbers = 0;
    var dates = 0;
    for (var r = 0; r < limit; r++) {
      final row = rows[r];
      if (c >= row.length) continue;
      final raw = row[c].trim();
      if (raw.isEmpty) continue;
      seen++;
      if (parseNumber(raw, NumberStyle.dot) != null) dotNumbers++;
      if (parseNumber(raw, NumberStyle.comma) != null) commaNumbers++;
      if (parseDate(raw) != null) dates++;
    }
    var type = ColumnType.text;
    var style = NumberStyle.dot;
    if (seen > 0) {
      final threshold = seen * 0.9;
      final numbers = dotNumbers > commaNumbers ? dotNumbers : commaNumbers;
      if (dates >= threshold && dates > 0) {
        type = ColumnType.date;
      } else if (numbers >= threshold) {
        type = ColumnType.number;
        // A comma-decimal column parses under both styles only when the values
        // are plain integers, so prefer dot unless comma parses strictly more.
        style = commaNumbers > dotNumbers ? NumberStyle.comma : NumberStyle.dot;
      }
    }
    metas.add(ColumnMeta(index: c, name: names[c], type: type, numberStyle: style));
  }
  return metas;
}
