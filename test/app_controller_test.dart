import 'dart:io';

import 'package:csviewer/src/model/filter.dart';
import 'package:csviewer/src/services/csv_loader.dart';
import 'package:csviewer/src/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

const String _sample = '''
nome,cidade,idade,valor,data
Ana,São Paulo,34,1200.50,2024-01-10
Bruno,Recife,28,980.00,2024-02-11
Carla,São Paulo,45,3300.75,2023-11-02
Diego,Curitiba,28,150.00,2024-03-01
Elisa,Recife,52,,2022-07-19
''';

/// Values of one column, in the order the grid would show them.
Future<List<String>> _column(AppController controller, int column) async {
  await controller.settle();
  final values = <String>[];
  for (var i = 0; i < controller.visibleRowCount; i++) {
    values.add((await controller.rowAt(i))!.cell(column));
  }
  return values;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Every behaviour is verified twice: with the file held in memory, and with
  // the streaming reader that only touches the blocks it needs.
  for (final mode in <ReadMode>[ReadMode.memory, ReadMode.streaming]) {
    group('modo ${mode.name}', () {
      late Directory dir;
      late String path;
      late AppController controller;

      setUp(() async {
        dir = await Directory.systemTemp.createTemp('csviewer_test');
        path = '${dir.path}/sample.csv';
        await File(path).writeAsString(_sample);
        controller = AppController();
        await controller.openPath(path, options: LoadOptions(mode: mode));
        await controller.settle();
      });

      tearDown(() async {
        controller.dispose();
        await dir.delete(recursive: true);
      });

      test('carrega cabeçalho, registros e tipos', () async {
        expect(controller.columnCount, 5);
        expect(controller.totalRows, 5);
        expect(controller.columns.map((c) => c.name).toList(),
            ['nome', 'cidade', 'idade', 'valor', 'data']);
        expect(controller.visibleRowCount, 5);
        expect(controller.isStreaming, mode == ReadMode.streaming);
      });

      test('ordena por coluna de texto em ordem crescente e decrescente', () async {
        controller.toggleSort(0);
        expect(await _column(controller, 0), ['Ana', 'Bruno', 'Carla', 'Diego', 'Elisa']);
        controller.toggleSort(0);
        expect(await _column(controller, 0), ['Elisa', 'Diego', 'Carla', 'Bruno', 'Ana']);
        controller.toggleSort(0);
        await controller.settle();
        expect(controller.sorts, isEmpty);
        expect(await _column(controller, 0), ['Ana', 'Bruno', 'Carla', 'Diego', 'Elisa']);
      });

      test('ordena números por valor, não como texto', () async {
        controller.setSort(3, true);
        expect(await _column(controller, 3), ['150.00', '980.00', '1200.50', '3300.75', '']);
      });

      test('ordenação por várias colunas usa a prioridade dos cliques', () async {
        controller.toggleSort(1); // cidade
        controller.toggleSort(2, additive: true); // idade
        expect(await _column(controller, 0), ['Diego', 'Bruno', 'Elisa', 'Ana', 'Carla']);
      });

      test('filtra por valor de coluna', () async {
        controller.addFilter(FilterRule(column: 1, op: FilterOp.equals, value: 'são paulo'));
        expect(await _column(controller, 0), ['Ana', 'Carla']);
      });

      test('concatena filtros com E', () async {
        controller.addFilter(FilterRule(column: 1, op: FilterOp.equals, value: 'Recife'));
        controller.addFilter(FilterRule(column: 2, op: FilterOp.less, value: '40'));
        expect(await _column(controller, 0), ['Bruno']);
      });

      test('concatena filtros com OU', () async {
        controller.addFilter(FilterRule(column: 1, op: FilterOp.equals, value: 'Curitiba'));
        controller.addFilter(
          FilterRule(column: 2, op: FilterOp.greater, value: '50', join: FilterJoin.or),
        );
        expect(await _column(controller, 0), ['Diego', 'Elisa']);
      });

      test('E tem precedência sobre OU, como em SQL', () async {
        // (cidade = Recife E idade < 40) OU cidade = Curitiba
        controller.addFilter(FilterRule(column: 1, op: FilterOp.equals, value: 'Recife'));
        controller.addFilter(FilterRule(column: 2, op: FilterOp.less, value: '40'));
        controller.addFilter(
          FilterRule(column: 1, op: FilterOp.equals, value: 'Curitiba', join: FilterJoin.or),
        );
        expect(await _column(controller, 0), ['Bruno', 'Diego']);
      });

      test('filtro entre valores usa comparação numérica', () async {
        controller.addFilter(
          FilterRule(column: 3, op: FilterOp.between, value: '900', value2: '1300'),
        );
        expect(await _column(controller, 0), ['Ana', 'Bruno']);
      });

      test('filtro por conjunto de valores', () async {
        controller.addFilter(
          FilterRule(column: 1, op: FilterOp.inSet, values: {'Recife', 'Curitiba'}),
        );
        expect(await _column(controller, 0), ['Bruno', 'Diego', 'Elisa']);
      });

      test('filtro por campo vazio', () async {
        controller.addFilter(FilterRule(column: 3, op: FilterOp.isEmpty));
        expect(await _column(controller, 0), ['Elisa']);
      });

      test('filtro de data compara cronologicamente', () async {
        controller.addFilter(FilterRule(column: 4, op: FilterOp.greater, value: '2024-02-01'));
        expect(await _column(controller, 0), ['Bruno', 'Diego']);
      });

      test('desativar um filtro o mantém na lista sem aplicá-lo', () async {
        controller.addFilter(FilterRule(column: 1, op: FilterOp.equals, value: 'Recife'));
        controller.toggleFilterEnabled(0);
        await controller.settle();
        expect(controller.filters.length, 1);
        expect(controller.visibleRowCount, 5);
      });

      test('busca rápida atravessa todas as colunas', () async {
        controller.setQuickSearch('curitiba');
        expect(await _column(controller, 0), ['Diego']);
      });

      test('filtros e ordenação se combinam', () async {
        controller.addFilter(FilterRule(column: 1, op: FilterOp.notEquals, value: 'Curitiba'));
        controller.setSort(2, false);
        expect(await _column(controller, 0), ['Elisa', 'Carla', 'Ana', 'Bruno']);
      });

      test('valores distintos de uma coluna', () async {
        expect(await controller.distinctValues(1),
            ['Curitiba', 'Recife', 'Recife', 'São Paulo']..removeAt(2));
      });

      test('exporta apenas a visão atual', () async {
        controller.addFilter(FilterRule(column: 1, op: FilterOp.equals, value: 'Recife'));
        controller.setSort(2, false);
        await controller.settle();
        final out = '${dir.path}/export.csv';
        final rows = await controller.export(out);
        expect(rows, 2);
        expect(File(out).readAsStringSync().trim().split('\n'), [
          'nome,cidade,idade,valor,data',
          'Elisa,Recife,52,,2022-07-19',
          'Bruno,Recife,28,980.00,2024-02-11',
        ]);
      });

      test('ocultar coluna a remove da exportação, mas não dos filtros', () async {
        controller.setColumnVisible(4, false);
        final out = '${dir.path}/export.csv';
        await controller.export(out);
        expect(File(out).readAsStringSync().split('\n').first, 'nome,cidade,idade,valor');
        controller.addFilter(FilterRule(column: 4, op: FilterOp.contains, value: '2024'));
        await controller.settle();
        expect(controller.visibleRowCount, 3);
      });

      test('recarregar com outro delimitador reprocessa o arquivo', () async {
        await controller.reload(LoadOptions(delimiter: ';', mode: mode));
        await controller.settle();
        expect(controller.columnCount, 1);
      });

      test('fechar o arquivo volta ao estado de quando o app abre', () async {
        controller.addFilter(FilterRule(column: 1, op: FilterOp.equals, value: 'Recife'));
        controller.toggleSort(2);
        controller.setQuickSearch('e');
        controller.setColumnVisible(3, false);
        controller.toggleInspector();
        await controller.settle();
        controller.selectViewRow(0);

        controller.closeDocument();
        final fresh = AppController();
        addTearDown(fresh.dispose);
        expect(controller.hasDocument, isFalse);
        expect(controller.source, isNull);
        expect(controller.filters, isEmpty);
        expect(controller.sorts, isEmpty);
        expect(controller.quickSearch, '');
        expect(controller.visibleColumns, isEmpty);
        expect(controller.selectedViewIndex, isNull);
        expect(controller.selectedRow, isNull);
        expect(controller.showInspector, fresh.showInspector);
        expect(controller.options.mode, fresh.options.mode);
        expect(controller.options.delimiter, fresh.options.delimiter);
        expect(controller.loading, isFalse);
        expect(controller.busy, isFalse);
        expect(controller.error, isNull);
        expect(controller.totalRows, 0);

        // Um filtro que ainda rodava não ressuscita nada nem deixa erro.
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(controller.error, isNull);
        expect(controller.hasDocument, isFalse);

        // E o próximo arquivo abre limpo.
        await controller.openPath(path, options: LoadOptions(mode: mode));
        await controller.settle();
        expect(controller.visibleRowCount, 5);
        expect(controller.visibleColumns.length, 5);
      });

      test('fechar durante a abertura descarta o arquivo que ainda carregava', () async {
        controller.closeDocument();
        final opening = controller.openPath(path, options: LoadOptions(mode: mode));
        expect(controller.loading, isTrue);
        controller.closeDocument();
        await opening;
        expect(controller.hasDocument, isFalse);
        expect(controller.loading, isFalse);
        expect(controller.error, isNull);
      });
    });
  }
}
