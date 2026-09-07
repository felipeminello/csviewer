import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:csviewer/src/services/csv_byte_records.dart';
import 'package:csviewer/src/services/csv_parser.dart';
import 'package:flutter_test/flutter_test.dart';

List<List<String>> _lazy(String text, [String delimiter = ',']) {
  final records = CsvByteRecords(Uint8List.fromList(utf8.encode(text)), delimiter);
  final rows = <List<String>>[];
  while (records.moveNext()) {
    rows.add(records.current.materialise());
  }
  return rows;
}

void _expectSameAsParser(String text, [String delimiter = ',']) {
  expect(_lazy(text, delimiter), parseCsvString(text, delimiter), reason: text);
}

void main() {
  group('CsvByteRecords', () {
    test('lê os mesmos registros que o parser', () {
      _expectSameAsParser('a,b,c\n1,2,3\n');
      _expectSameAsParser('a,b\n"x, y",2\n');
      _expectSameAsParser('a,b\n"quebra\nde linha",2\n');
      _expectSameAsParser('a,b\n"aspas ""duplas""",2\n');
      _expectSameAsParser('a,b\r\n1,2\r\n3,4\r\n');
      _expectSameAsParser('a,b\n\n1,2\n\n\n3,4\n');
      _expectSameAsParser('a,b,c\n1,,\n');
      _expectSameAsParser('a,b\n1,2');
      _expectSameAsParser('a;b\n"x;y";2\n', ';');
      _expectSameAsParser('a,b\n"sem fim,2\n');
      _expectSameAsParser('a,b\n"lixo"depois,2\n');
      _expectSameAsParser('a,b\n"",2\n');
    });

    test('preserva acentos e caracteres multibyte', () {
      expect(_lazy('a\nJoão çé 日本語\n')[1][0], 'João çé 日本語');
    });

    test('só decodifica o campo que for lido', () {
      final records = CsvByteRecords(Uint8List.fromList(utf8.encode('a,b,c\n')), ',');
      expect(records.moveNext(), isTrue);
      expect(records.current[1], 'b');
      expect(records.current.length, 3);
    });

    test('casa com o parser em conteúdo aleatório', () {
      final random = Random(19);
      for (var round = 0; round < 200; round++) {
        final buffer = StringBuffer();
        final rows = random.nextInt(6) + 1;
        for (var r = 0; r < rows; r++) {
          final fields = random.nextInt(4) + 1;
          final parts = <String>[];
          for (var f = 0; f < fields; f++) {
            switch (random.nextInt(6)) {
              case 0:
                parts.add('');
                break;
              case 1:
                parts.add('texto$r$f');
                break;
              case 2:
                parts.add('"com, vírgula"');
                break;
              case 3:
                parts.add('"quebra\nlinha"');
                break;
              case 4:
                parts.add('"aspas ""x"""');
                break;
              default:
                parts.add('  espaços  ');
            }
          }
          buffer.write(parts.join(','));
          buffer.write(random.nextBool() ? '\n' : '\r\n');
          if (random.nextInt(5) == 0) buffer.write('\n');
        }
        _expectSameAsParser(buffer.toString());
      }
    });
  });
}
