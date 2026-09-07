import 'dart:io';
import 'dart:math';

import 'package:csviewer/src/data/csv_source.dart';
import 'package:csviewer/src/model/filter.dart';
import 'package:csviewer/src/services/csv_loader.dart';
import 'package:csviewer/src/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const int _rowCount = 5000; // ~20 blocks of 256 records

/// A file with the awkward shapes real exports have: quoted separators,
/// embedded newlines, escaped quotes, empty fields, blank lines and CRLF.
String _buildCsv() {
  final random = Random(11);
  final cities = ['São Paulo', 'Recife', 'Curitiba', 'Belém', 'Porto Alegre'];
  final buffer = StringBuffer('id,cidade,valor,obs\n');
  for (var i = 0; i < _rowCount; i++) {
    final city = cities[i % cities.length];
    final value = (random.nextDouble() * 1000).toStringAsFixed(2);
    switch (i % 7) {
      case 0:
        buffer.write('$i,$city,$value,"nota, com vírgula"\n');
        break;
      case 1:
        buffer.write('$i,$city,$value,"linha1\nlinha2"\r\n');
        break;
      case 2:
        buffer.write('\n$i,$city,$value,"aspas ""duplas"""\n');
        break;
      case 3:
        buffer.write('$i,$city,,\n');
        break;
      default:
        buffer.write('$i,$city,$value,simples\n');
    }
  }
  return buffer.toString();
}

Future<List<List<String>>> _viewRows(CsvSource source) async {
  final rows = <List<String>>[];
  for (var i = 0; i < source.viewRowCount; i++) {
    rows.add((await source.rowAt(i))!.values);
  }
  return rows;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late String path;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('csviewer_stream');
    path = '${dir.path}/grande.csv';
    await File(path).writeAsString(_buildCsv());
  });

  tearDown(() async => dir.delete(recursive: true));

  Future<CsvSource> open(ReadMode mode, {int sortLimit = 2000000}) async {
    final source = await openCsvSource(path, LoadOptions(mode: mode), sortLimit: sortLimit);
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (source.indexing && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    return source;
  }

  test('indexa todos os registros do arquivo', () async {
    final source = await open(ReadMode.streaming);
    expect(source.isStreaming, isTrue);
    expect(source.totalRows, _rowCount);
    expect(source.viewRowCount, _rowCount);
    expect(source.columns.map((c) => c.name).toList(), ['id', 'cidade', 'valor', 'obs']);
    source.dispose();
  });

  test('lê os mesmos registros que o leitor em memória, em qualquer posição', () async {
    final streaming = await open(ReadMode.streaming);
    final memory = await open(ReadMode.memory);
    expect(streaming.totalRows, memory.totalRows);
    for (final position in [0, 1, 255, 256, 257, 1000, 2999, _rowCount - 1]) {
      final fromDisk = await streaming.rowAt(position);
      final fromMemory = await memory.rowAt(position);
      expect(fromDisk!.values, fromMemory!.values, reason: 'registro $position');
      expect(fromDisk.sourceRow, position);
    }
    streaming.dispose();
    memory.dispose();
  });

  test('campos com quebra de linha e aspas sobrevivem à leitura por blocos', () async {
    final source = await open(ReadMode.streaming);
    expect((await source.rowAt(1))!.cell(3), 'linha1\nlinha2');
    expect((await source.rowAt(2))!.cell(3), 'aspas "duplas"');
    expect((await source.rowAt(3))!.cell(3), '');
    source.dispose();
  });

  test('filtrar e ordenar dá o mesmo resultado nos dois modos', () async {
    final filters = [
      FilterRule(column: 1, op: FilterOp.equals, value: 'Recife'),
      FilterRule(column: 2, op: FilterOp.greater, value: '500'),
    ];
    const sorts = [SortSpec(2, ascending: false)];

    final streaming = await open(ReadMode.streaming);
    final memory = await open(ReadMode.memory);
    final streamingResult = await streaming.applyView(filters, '', sorts);
    final memoryResult = await memory.applyView(filters, '', sorts);

    expect(streamingResult.rowCount, memoryResult.rowCount);
    expect(streamingResult.rowCount, greaterThan(0));
    expect(streamingResult.sortApplied, isTrue);
    expect(await _viewRows(streaming), await _viewRows(memory));
    streaming.dispose();
    memory.dispose();
  });

  test('busca rápida percorre o arquivo inteiro', () async {
    final streaming = await open(ReadMode.streaming);
    final memory = await open(ReadMode.memory);
    final a = await streaming.applyView(const [], 'porto alegre', const []);
    final b = await memory.applyView(const [], 'porto alegre', const []);
    expect(a.rowCount, b.rowCount);
    expect(a.rowCount, _rowCount ~/ 5);
    streaming.dispose();
    memory.dispose();
  });

  test('valores distintos são iguais nos dois modos', () async {
    final streaming = await open(ReadMode.streaming);
    final memory = await open(ReadMode.memory);
    expect(await streaming.distinctValues(1), await memory.distinctValues(1));
    streaming.dispose();
    memory.dispose();
  });

  test('exportação transmitida para o disco casa com a do modo memória', () async {
    final filters = [FilterRule(column: 1, op: FilterOp.equals, value: 'Curitiba')];
    final streaming = await open(ReadMode.streaming);
    final memory = await open(ReadMode.memory);
    await streaming.applyView(filters, '', const [SortSpec(0)]);
    await memory.applyView(filters, '', const [SortSpec(0)]);

    final streamingOut = '${dir.path}/streaming.csv';
    final memoryOut = '${dir.path}/memoria.csv';
    final rows = await streaming.exportTo(streamingOut, [0, 1, 2, 3]);
    await memory.exportTo(memoryOut, [0, 1, 2, 3]);

    expect(rows, streaming.viewRowCount);
    expect(File(streamingOut).readAsStringSync(), File(memoryOut).readAsStringSync());
    streaming.dispose();
    memory.dispose();
  });

  test('ordenação acima do limite é recusada em vez de estourar a memória', () async {
    final source = await open(ReadMode.streaming, sortLimit: 100);
    final result = await source.applyView(const [], '', const [SortSpec(0)]);
    expect(result.sortApplied, isFalse);
    expect(result.rowCount, _rowCount); // os registros continuam disponíveis
    source.dispose();
  });

  test('o controller desfaz a ordenação recusada e avisa o usuário', () async {
    final controller = AppController();
    await controller.openPath(path,
        options: const LoadOptions(mode: ReadMode.streaming), sortLimit: 100);
    await controller.settle();
    controller.setSort(0, true);
    await controller.settle();
    expect(controller.sorts, isEmpty);
    expect(controller.notice, contains('Filtre antes de ordenar'));
    expect(controller.visibleRowCount, _rowCount);
    controller.dispose();
  });

  test('depois de filtrar, a ordenação volta a caber no limite', () async {
    final controller = AppController();
    await controller.openPath(path,
        options: const LoadOptions(mode: ReadMode.streaming), sortLimit: 100);
    await controller.settle();
    controller.addFilter(FilterRule(column: 1, op: FilterOp.equals, value: 'Belém'));
    controller.addFilter(FilterRule(column: 2, op: FilterOp.greater, value: '900'));
    await controller.settle();
    expect(controller.visibleRowCount, lessThan(100));
    controller.setSort(2, false);
    await controller.settle();
    expect(controller.sorts, hasLength(1));
    final first = (await controller.rowAt(0))!.cell(2);
    final second = (await controller.rowAt(1))!.cell(2);
    expect(double.parse(first), greaterThanOrEqualTo(double.parse(second)));
    controller.dispose();
  });
}
