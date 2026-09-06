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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late String path;
  late AppController controller;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('csviewer_test');
    path = '${dir.path}/sample.csv';
    await File(path).writeAsString(_sample);
    controller = AppController();
    await controller.openPath(path);
  });

  tearDown(() async {
    controller.dispose();
    await dir.delete(recursive: true);
  });

  test('carrega cabeçalho, registros e tipos', () {
    final table = controller.table!;
    expect(table.columnCount, 5);
    expect(table.rowCount, 5);
    expect(table.columns.map((c) => c.name).toList(),
        ['nome', 'cidade', 'idade', 'valor', 'data']);
    expect(controller.visibleRowCount, 5);
  });

  test('ordena por coluna de texto em ordem crescente e decrescente', () {
    controller.toggleSort(0);
    expect(_column(controller, 0), ['Ana', 'Bruno', 'Carla', 'Diego', 'Elisa']);
    controller.toggleSort(0);
    expect(_column(controller, 0), ['Elisa', 'Diego', 'Carla', 'Bruno', 'Ana']);
    controller.toggleSort(0);
    expect(controller.sorts, isEmpty);
    expect(_column(controller, 0), ['Ana', 'Bruno', 'Carla', 'Diego', 'Elisa']);
  });

  test('ordena números por valor, não como texto', () {
    controller.setSort(3, true);
    expect(_column(controller, 3), ['150.00', '980.00', '1200.50', '3300.75', '']);
  });

  test('ordenação por várias colunas usa a prioridade dos cliques', () {
    controller.toggleSort(1); // cidade
    controller.toggleSort(2, additive: true); // idade
    expect(_column(controller, 0), ['Diego', 'Bruno', 'Elisa', 'Ana', 'Carla']);
  });

  test('filtra por valor de coluna', () {
    controller.addFilter(FilterRule(column: 1, op: FilterOp.equals, value: 'são paulo'));
    expect(_column(controller, 0), ['Ana', 'Carla']);
  });

  test('concatena filtros com E', () {
    controller.addFilter(FilterRule(column: 1, op: FilterOp.equals, value: 'Recife'));
    controller.addFilter(FilterRule(column: 2, op: FilterOp.less, value: '40'));
    expect(_column(controller, 0), ['Bruno']);
  });

  test('concatena filtros com OU', () {
    controller.addFilter(FilterRule(column: 1, op: FilterOp.equals, value: 'Curitiba'));
    controller.addFilter(
      FilterRule(column: 2, op: FilterOp.greater, value: '50', join: FilterJoin.or),
    );
    expect(_column(controller, 0), ['Diego', 'Elisa']);
  });

  test('E tem precedência sobre OU, como em SQL', () {
    // (cidade = Recife E idade < 40) OU cidade = Curitiba
    controller.addFilter(FilterRule(column: 1, op: FilterOp.equals, value: 'Recife'));
    controller.addFilter(FilterRule(column: 2, op: FilterOp.less, value: '40'));
    controller.addFilter(
      FilterRule(column: 1, op: FilterOp.equals, value: 'Curitiba', join: FilterJoin.or),
    );
    expect(_column(controller, 0), ['Bruno', 'Diego']);
  });

  test('filtro entre valores usa comparação numérica', () {
    controller.addFilter(
      FilterRule(column: 3, op: FilterOp.between, value: '900', value2: '1300'),
    );
    expect(_column(controller, 0), ['Ana', 'Bruno']);
  });

  test('filtro por conjunto de valores', () {
    controller.addFilter(
      FilterRule(column: 1, op: FilterOp.inSet, values: {'Recife', 'Curitiba'}),
    );
    expect(_column(controller, 0), ['Bruno', 'Diego', 'Elisa']);
  });

  test('filtro por campo vazio', () {
    controller.addFilter(FilterRule(column: 3, op: FilterOp.isEmpty));
    expect(_column(controller, 0), ['Elisa']);
  });

  test('filtro de data compara cronologicamente', () {
    controller.addFilter(FilterRule(column: 4, op: FilterOp.greater, value: '2024-02-01'));
    expect(_column(controller, 0), ['Bruno', 'Diego']);
  });

  test('desativar um filtro o mantém na lista sem aplicá-lo', () {
    controller.addFilter(FilterRule(column: 1, op: FilterOp.equals, value: 'Recife'));
    controller.toggleFilterEnabled(0);
    expect(controller.filters.length, 1);
    expect(controller.visibleRowCount, 5);
  });

  test('busca rápida atravessa todas as colunas', () {
    controller.setQuickSearch('curitiba');
    expect(_column(controller, 0), ['Diego']);
  });

  test('filtros e ordenação se combinam', () {
    controller.addFilter(FilterRule(column: 1, op: FilterOp.notEquals, value: 'Curitiba'));
    controller.setSort(2, false);
    expect(_column(controller, 0), ['Elisa', 'Carla', 'Ana', 'Bruno']);
  });

  test('exporta apenas a visão atual', () {
    controller.addFilter(FilterRule(column: 1, op: FilterOp.equals, value: 'Recife'));
    controller.setSort(2, false);
    final csv = controller.exportCsv();
    expect(csv.trim().split('\n'), [
      'nome,cidade,idade,valor,data',
      'Elisa,Recife,52,,2022-07-19',
      'Bruno,Recife,28,980.00,2024-02-11',
    ]);
  });

  test('ocultar coluna a remove da exportação, mas não dos filtros', () {
    controller.setColumnVisible(4, false);
    expect(controller.exportCsv().split('\n').first, 'nome,cidade,idade,valor');
    controller.addFilter(FilterRule(column: 4, op: FilterOp.contains, value: '2024'));
    expect(controller.visibleRowCount, 3);
  });

  test('recarregar com outro delimitador reprocessa o arquivo', () async {
    await controller.reload(const LoadOptions(delimiter: ';'));
    expect(controller.table!.columnCount, 1);
  });
}

List<String> _column(AppController controller, int column) {
  final table = controller.table!;
  return controller.viewRows.map((r) => table.cell(r, column)).toList();
}
