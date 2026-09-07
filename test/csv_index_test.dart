import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:csviewer/src/services/csv_index.dart';
import 'package:csviewer/src/services/csv_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Feeds [text] to the indexer in chunks of [chunkSize] bytes.
CsvIndexer _index(String text, {int chunkSize = 7, String delimiter = ',', int headerRows = 1, int blockRows = 4}) {
  final bytes = Uint8List.fromList(utf8.encode(text));
  final indexer = CsvIndexer(delimiter: delimiter, headerRows: headerRows, blockRows: blockRows);
  for (var i = 0; i < bytes.length; i += chunkSize) {
    indexer.feed(Uint8List.sublistView(bytes, i, min(i + chunkSize, bytes.length)));
  }
  indexer.finish(bytes.length);
  return indexer;
}

/// Every block must decode to exactly the records the in-memory parser sees.
void _expectBlocksMatchParser(String text, {int chunkSize = 7, int blockRows = 4}) {
  final bytes = Uint8List.fromList(utf8.encode(text));
  final indexer = _index(text, chunkSize: chunkSize, blockRows: blockRows);
  final expected = parseCsvString(text, ',').skip(1).toList();

  expect(indexer.dataRows, expected.length, reason: 'contagem de registros');

  final map = CsvBlockMap(indexer.blockOffsets, indexer.endOfCountedData, blockRows: blockRows);
  final actual = <List<String>>[];
  for (var b = 0; b < map.blockCount; b++) {
    final range = map.range(b, 1);
    final chunk = utf8.decode(Uint8List.sublistView(bytes, range.start, range.end));
    actual.addAll(parseCsvString(chunk, ','));
  }
  expect(actual, expected);
}

void main() {
  group('CsvIndexer', () {
    test('conta registros simples', () {
      final indexer = _index('a,b\n1,2\n3,4\n5,6\n');
      expect(indexer.dataRows, 3);
      expect(indexer.blockOffsets.first, 4); // logo após "a,b\n"
    });

    test('ignora linhas em branco, como o parser', () {
      _expectBlocksMatchParser('a,b\n1,2\n\n3,4\n\n\n5,6\n');
    });

    test('não quebra registros em campos com aspas e quebra de linha', () {
      _expectBlocksMatchParser('a,b\n"linha1\nlinha2",2\n"x""y",3\n4,5\n');
    });

    test('aceita CRLF e CR, inclusive na fronteira de chunk', () {
      for (final chunk in [1, 2, 3, 5, 8, 64]) {
        _expectBlocksMatchParser('a,b\r\n1,2\r\n"c\r\nd",4\r\n', chunkSize: chunk);
      }
    });

    test('vírgula dentro de campo entre aspas não conta como campo novo', () {
      _expectBlocksMatchParser('a,b\n"x, y",2\n"z, w",3\n');
    });

    test('último registro sem quebra de linha final é contado', () {
      _expectBlocksMatchParser('a,b\n1,2\n3,4');
    });

    test('sem cabeçalho conta todas as linhas', () {
      final indexer = _index('1,2\n3,4\n', headerRows: 0);
      expect(indexer.dataRows, 2);
      expect(indexer.blockOffsets.first, 0);
    });

    test('offsets de bloco caem no início de cada bloco de registros', () {
      final linhas = List.generate(20, (i) => 'v$i').join('\n');
      final indexer = _index('h\n$linhas', blockRows: 4);
      expect(indexer.dataRows, 20);
      expect(indexer.blockOffsets.length, 5);
    });

    test('arquivo grande e irregular casa com o parser em qualquer tamanho de chunk', () {
      final random = Random(3);
      final buffer = StringBuffer('col_a,col_b,col_c\n');
      for (var i = 0; i < 400; i++) {
        final kind = random.nextInt(6);
        switch (kind) {
          case 0:
            buffer.write('$i,simples,ok\n');
            break;
          case 1:
            buffer.write('$i,"com, vírgula",ok\r\n');
            break;
          case 2:
            buffer.write('$i,"quebra\nde linha",ok\n');
            break;
          case 3:
            buffer.write('$i,"aspas ""duplas""",ok\n');
            break;
          case 4:
            buffer.write('\n$i,depois de linha vazia,ok\n');
            break;
          default:
            buffer.write('$i,,\n');
        }
      }
      for (final chunk in [1, 3, 17, 512, 100000]) {
        _expectBlocksMatchParser(buffer.toString(), chunkSize: chunk, blockRows: 8);
      }
    });
  });
}
