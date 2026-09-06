import 'dart:convert';
import 'dart:typed_data';

import 'package:csviewer/src/model/column_meta.dart';
import 'package:csviewer/src/services/csv_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCsvString', () {
    test('lê campos simples e ignora linhas em branco', () {
      final rows = parseCsvString('a,b,c\n1,2,3\n\n4,5,6\n', ',');
      expect(rows, [
        ['a', 'b', 'c'],
        ['1', '2', '3'],
        ['4', '5', '6'],
      ]);
    });

    test('respeita aspas, vírgulas internas e aspas escapadas', () {
      final rows = parseCsvString('nome,obs\n"Silva, João","disse ""oi"""\n', ',');
      expect(rows[1], ['Silva, João', 'disse "oi"']);
    });

    test('aceita quebra de linha dentro de campo entre aspas', () {
      final rows = parseCsvString('a,b\n"linha1\nlinha2",x\n', ',');
      expect(rows.length, 2);
      expect(rows[1][0], 'linha1\nlinha2');
    });

    test('aceita CRLF e CR', () {
      expect(parseCsvString('a,b\r\n1,2\r\n', ',').length, 2);
      expect(parseCsvString('a,b\r1,2\r', ',').length, 2);
    });

    test('campo vazio no fim da linha é preservado', () {
      expect(parseCsvString('a,b,c\n1,,\n', ',')[1], ['1', '', '']);
    });

    test('aspas não fechadas não perdem o restante do arquivo', () {
      final rows = parseCsvString('a,b\n"sem fim,2\n', ',');
      expect(rows.length, 2);
      expect(rows[1].first, contains('sem fim'));
    });
  });

  group('detectDelimiter', () {
    test('detecta ponto e vírgula', () {
      expect(detectDelimiter('a;b;c\n1;2;3\n4;5;6\n'), ';');
    });

    test('detecta tabulação', () {
      expect(detectDelimiter('a\tb\tc\n1\t2\t3\n'), '\t');
    });

    test('não se confunde com vírgulas dentro de campos entre aspas', () {
      expect(detectDelimiter('a;b\n"x, y";2\n"w, z";3\n'), ';');
    });
  });

  group('decodeBytes', () {
    test('remove BOM UTF-8', () {
      final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('a,b')]);
      expect(decodeBytes(bytes).text, 'a,b');
    });

    test('cai para Latin-1 quando não é UTF-8 válido', () {
      final bytes = Uint8List.fromList([0x4A, 0x6F, 0xE3, 0x6F]); // "João" em latin-1
      final decoded = decodeBytes(bytes);
      expect(decoded.text, 'João');
      expect(decoded.encodingName, 'Latin-1');
    });
  });

  group('inferColumns', () {
    test('reconhece números, datas e texto', () {
      final metas = inferColumns(
        ['id', 'data', 'nome'],
        [
          ['1', '2024-01-05', 'Ana'],
          ['2', '2024-02-06', 'Beto'],
        ],
      );
      expect(metas[0].type, ColumnType.number);
      expect(metas[1].type, ColumnType.date);
      expect(metas[2].type, ColumnType.text);
    });

    test('reconhece decimal com vírgula', () {
      final metas = inferColumns(
        ['valor'],
        [
          ['1.234,56'],
          ['10,5'],
          ['7,25'],
        ],
      );
      expect(metas[0].type, ColumnType.number);
      expect(metas[0].numberStyle, NumberStyle.comma);
      expect(metas[0].number('1.234,56'), 1234.56);
    });
  });

  group('parseNumber', () {
    test('estilo ponto aceita separador de milhar', () {
      expect(parseNumber('1,234.56', NumberStyle.dot), 1234.56);
      expect(parseNumber('10,5', NumberStyle.dot), isNull);
    });

    test('trata símbolos de moeda, percentual e parênteses', () {
      expect(parseNumber('R\$ 1.234,50', NumberStyle.comma), 1234.50);
      expect(parseNumber('12,5%', NumberStyle.comma), 12.5);
      expect(parseNumber('(30)', NumberStyle.dot), -30);
    });
  });

  group('parseDate', () {
    test('aceita ISO e dd/MM/yyyy', () {
      expect(parseDate('2024-03-15'), DateTime(2024, 3, 15));
      expect(parseDate('15/03/2024'), DateTime(2024, 3, 15));
      expect(parseDate('15/03/2024 10:30'), DateTime(2024, 3, 15, 10, 30));
    });

    test('rejeita texto comum', () {
      expect(parseDate('abc'), isNull);
      expect(parseDate('99/99/9999'), isNull);
    });
  });
}
