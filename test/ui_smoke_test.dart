import 'dart:io';
import 'dart:ui' as ui;

import 'package:csviewer/src/model/filter.dart';
import 'package:csviewer/src/state/app_controller.dart';
import 'package:csviewer/src/ui/home_page.dart';
import 'package:csviewer/src/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const String _sample = '''
pedido;cliente;cidade;categoria;quantidade;valor_total;data_pedido;status
PED-00001;Felipe Nunes;Rio de Janeiro;Vestuário;2;361,61;18/02/2024;Pago
PED-00002;Diego Alves;São Paulo;Eletrônicos;14;2015,95;08/02/2025;Enviado
PED-00003;Ana Souza;Recife;Livros;3;89,90;02/03/2023;Pendente
PED-00004;Carla Dias;Curitiba;Alimentos;7;1240,00;22/11/2024;Pago
PED-00005;Bruno Lima;São Paulo;Casa & Jardim;1;4780,25;05/01/2025;Cancelado
PED-00006;Elisa Rocha;Salvador;Eletrônicos;9;733,10;30/06/2024;Pago
PED-00007;João Vidal;Belo Horizonte;Livros;12;58,40;14/09/2023;Enviado
PED-00008;Gabriela Melo;Recife;Vestuário;5;902,00;27/04/2025;Pendente
''';

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family)
    ..addFont(Future.value(File(path).readAsBytesSync().buffer.asByteData()));
  await loader.load();
}

void main() {
  late Directory dir;
  late AppController controller;

  setUpAll(() async {
    // Real fonts so the rendered screenshots are legible.
    var dir = File(Platform.resolvedExecutable).parent;
    while (dir.path != dir.parent.path) {
      final candidate = Directory('${dir.path}/material_fonts');
      if (candidate.existsSync()) {
        await _loadFont('MaterialIcons', '${candidate.path}/MaterialIcons-Regular.otf');
        await _loadFont('Roboto', '${candidate.path}/Roboto-Regular.ttf');
        break;
      }
      dir = dir.parent;
    }
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('csviewer_ui');
    await File('${dir.path}/pedidos.csv').writeAsString(_sample);
    controller = AppController();
    await controller.openPath('${dir.path}/pedidos.csv');
  });

  tearDown(() async {
    controller.dispose();
    await dir.delete(recursive: true);
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(2400, 1500);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        child: MaterialApp(
          theme: AppTheme.light(fontFamily: 'Roboto'),
          home: HomePage(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // Rasterising needs a real event loop, hence runAsync.
  Future<void> capture(WidgetTester tester, String name) async {
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final out = Directory('build/screenshots')..createSync(recursive: true);
      File('${out.path}/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    });
  }

  testWidgets('mostra cabeçalhos, registros e barra de status', (tester) async {
    await pumpApp(tester);
    expect(find.text('pedido'), findsOneWidget);
    expect(find.text('valor_total'), findsOneWidget);
    expect(find.text('PED-00001'), findsOneWidget);
    expect(find.textContaining('8 registros'), findsOneWidget);
    await capture(tester, '01-grade');
  });

  testWidgets('clicar no cabeçalho ordena crescente e depois decrescente', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('cliente'));
    await tester.pumpAndSettle();
    expect(controller.sorts.single.column, 1);
    expect(controller.sorts.single.ascending, isTrue);
    final table = controller.table!;
    expect(table.cell(controller.viewRows.first, 1), 'Ana Souza');

    await tester.tap(find.text('cliente'));
    await tester.pumpAndSettle();
    expect(controller.sorts.single.ascending, isFalse);
    expect(table.cell(controller.viewRows.first, 1), 'João Vidal');
    await capture(tester, '02-ordenado');
  });

  testWidgets('barra de filtros mostra a cadeia com E / OU', (tester) async {
    controller.addFilter(FilterRule(column: 2, op: FilterOp.inSet, values: {'Recife', 'São Paulo'}));
    controller.addFilter(FilterRule(column: 4, op: FilterOp.greater, value: '4'));
    controller.addFilter(
      FilterRule(column: 7, op: FilterOp.equals, value: 'Pago', join: FilterJoin.or),
    );
    await pumpApp(tester);
    expect(find.text('E'), findsOneWidget);
    expect(find.text('OU'), findsOneWidget);
    expect(find.textContaining('de 8 registros'), findsOneWidget);
    await capture(tester, '03-filtros');
  });

  testWidgets('o diálogo de filtro abre pelo botão da barra de ferramentas', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Filtro'));
    await tester.pumpAndSettle();
    expect(find.text('Novo filtro'), findsOneWidget);
    expect(find.text('Coluna'), findsOneWidget);
    expect(find.text('Condição'), findsOneWidget);
    await capture(tester, '04-dialogo-filtro');
  });

  testWidgets('o painel do registro mostra todos os campos da linha', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('PED-00003'));
    controller.toggleInspector();
    await tester.pumpAndSettle();
    expect(find.text('Ana Souza'), findsNWidgets(2)); // grade + painel
    await capture(tester, '05-painel-registro');
  });

  testWidgets('busca rápida filtra e destaca', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.byType(TextField).last, 'recife');
    await tester.pumpAndSettle();
    expect(controller.visibleRowCount, 2);
    await capture(tester, '06-busca');
  });
}
