import 'dart:io';
import 'dart:ui' as ui;

import 'package:csviewer/src/model/filter.dart';
import 'package:csviewer/src/services/csv_loader.dart';
import 'package:csviewer/src/state/app_controller.dart';
import 'package:csviewer/src/ui/data_grid.dart';
import 'package:csviewer/src/ui/home_page.dart';
import 'package:csviewer/src/ui/theme.dart';
import 'package:flutter/gestures.dart';
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
    await controller.settle();
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
    expect(controller.rowIfReady(0)!.cell(1), 'Ana Souza');

    await tester.tap(find.text('cliente'));
    await tester.pumpAndSettle();
    expect(controller.sorts.single.ascending, isFalse);
    expect(controller.rowIfReady(0)!.cell(1), 'João Vidal');
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

  testWidgets('a barra de ferramentas nunca corta o botão Exportar', (tester) async {
    // O bloco de botões dividia o espaço livre com o nome do arquivo e sobrava
    // pouco: entre ~860 e ~1200 de largura o "Exportar" ficava pela metade.
    for (final width in <double>[520, 700, 860, 960, 1100, 1200, 1440, 1800]) {
      tester.view.physicalSize = Size(width, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light(fontFamily: 'Roboto'),
        home: HomePage(controller: controller),
      ));
      await tester.pumpAndSettle();

      // Em janelas estreitas os rótulos viram ícones — mas o botão continua lá.
      final button = find.byTooltip('Salvar a visão atual (filtrada e ordenada) como CSV');
      expect(button, findsOneWidget, reason: 'sem botão Exportar em $width');
      final viewport = find.ancestor(of: button, matching: find.byType(SingleChildScrollView));
      expect(tester.getRect(button).right,
          lessThanOrEqualTo(tester.getRect(viewport.first).right + 0.5),
          reason: 'Exportar cortado em $width');
      // Fechar fica fora do bloco rolável, entre o nome e a busca.
      final close = find.byTooltip('Fechar arquivo (⌘W)');
      expect(close, findsOneWidget, reason: 'sem botão Fechar em $width');
      expect(tester.getRect(close).right,
          lessThanOrEqualTo(tester.getRect(find.byType(TextField).first).left + 0.5),
          reason: 'Fechar sobreposto à busca em $width');
      // A busca tem padding próprio: precisa caber nos 46px da barra.
      expect(tester.getSize(find.byType(TextField).first).height, lessThan(42));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('as três janelas de diálogo cabem numa tela pequena', (tester) async {
    tester.view.physicalSize = const Size(900, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      child: MaterialApp(
        theme: AppTheme.light(fontFamily: 'Roboto'),
        home: HomePage(controller: controller),
      ),
    ));
    await tester.pumpAndSettle();

    Future<void> open(String tooltip, String title, String shot) async {
      await tester.tap(find.byTooltip(tooltip));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      // Um estouro de layout (a faixa listrada) chega aqui como exceção.
      expect(tester.takeException(), isNull, reason: 'layout de "$title" estourou');
      await capture(tester, shot);
      await tester.tap(find.text('Cancelar').hitTestable().first);
      await tester.pumpAndSettle();
    }

    await open('Adicionar filtro (⌘L)', 'Novo filtro', '08-dialogo-filtro-pequeno');
    await open('Delimitador, codificação e cabeçalho', 'Opções de leitura', '09-dialogo-leitura');

    // A janela de colunas fecha em "Concluir" (o botão da barra, nessa
    // largura, ainda mostra o rótulo).
    await tester.tap(find.widgetWithText(TextButton, 'Colunas'));
    await tester.pumpAndSettle();
    expect(find.text('8 de 8 visíveis na grade'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await capture(tester, '10-dialogo-colunas');
    await tester.tap(find.text('Concluir'));
    await tester.pumpAndSettle();
  });

  testWidgets('a lista de valores do filtro rola dentro da janela', (tester) async {
    tester.view.physicalSize = const Size(900, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(fontFamily: 'Roboto'),
      home: HomePage(controller: controller),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Adicionar filtro (⌘L)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('contém'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('é um de').last);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(find.text('Valores'), findsOneWidget);
    expect(find.textContaining('selecionados'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('o painel do registro mostra todos os campos da linha', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('PED-00003'));
    controller.toggleInspector();
    await tester.pumpAndSettle();
    expect(find.text('Ana Souza'), findsNWidgets(2)); // grade + painel
    await capture(tester, '05-painel-registro');
  });

  testWidgets('no modo streaming a grade preenche as linhas conforme lê o disco',
      (tester) async {
    final streaming = AppController();
    addTearDown(streaming.dispose);
    // Abertura e indexação usam temporizadores reais, fora do relógio falso do
    // teste de widget.
    await tester.runAsync(() async {
      await streaming.openPath('${dir.path}/pedidos.csv',
          options: const LoadOptions(mode: ReadMode.streaming));
      await streaming.settle();
    });
    expect(streaming.isStreaming, isTrue);
    expect(streaming.visibleRowCount, 8);

    tester.view.physicalSize = const Size(2400, 1500);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        child: MaterialApp(
          theme: AppTheme.light(fontFamily: 'Roboto'),
          home: HomePage(controller: streaming),
        ),
      ),
    );
    // Primeiro quadro: os registros ainda estão sendo lidos do disco.
    await tester.pump();
    expect(find.text('PED-00001'), findsNothing);

    // A janela chega do isolate e a grade se preenche.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pumpAndSettle();
    expect(find.text('PED-00001'), findsOneWidget);
    expect(find.text('Gabriela Melo'), findsOneWidget);
    expect(find.textContaining('8 registros'), findsOneWidget);
    await capture(tester, '07-streaming');
  });

  /// Grade que transborda nos dois eixos: muitas linhas para a lista vertical
  /// ter para onde rolar, e colunas largas para a grade passar da janela.
  Future<AppController> pumpWideGrid(WidgetTester tester) async {
    final buffer = StringBuffer(_sample.split('\n').first)..writeln();
    for (var i = 0; i < 400; i++) {
      buffer.writeln('PED-${(i + 1).toString().padLeft(5, '0')};Cliente $i;Recife;Livros;'
          '3;89,90;02/03/2023;Pago');
    }
    final wide = AppController();
    addTearDown(wide.dispose);
    // I/O real precisa do relógio real, fora do tempo falso do teste.
    await tester.runAsync(() async {
      await File('${dir.path}/muitos.csv').writeAsString(buffer.toString());
      await wide.openPath('${dir.path}/muitos.csv');
      await wide.settle();
    });

    tester.view.physicalSize = const Size(2400, 1500);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        child: MaterialApp(
          theme: AppTheme.light(fontFamily: 'Roboto'),
          home: HomePage(controller: wide),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var c = 0; c < wide.columns.length; c++) {
      wide.setColumnWidth(c, 320);
    }
    await tester.pumpAndSettle();
    return wide;
  }

  testWidgets('roda e trackpad rolam a grade na horizontal', (tester) async {
    await pumpWideGrid(tester);

    final ScrollController horizontal = tester
        .widget<SingleChildScrollView>(
          find.descendant(
            of: find.byType(DataGrid),
            matching: find.byType(SingleChildScrollView),
          ),
        )
        .controller!;
    final ScrollController vertical = tester
        .widget<ListView>(find.descendant(
          of: find.byType(DataGrid),
          matching: find.byType(ListView),
        ))
        .controller!;
    expect(horizontal.position.maxScrollExtent, greaterThan(0));
    expect(vertical.position.maxScrollExtent, greaterThan(0));

    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(find.byType(DataGrid))));
    // Gesto diagonal do trackpad: a lista vertical engolia o evento inteiro e
    // o componente horizontal se perdia.
    await tester.sendEventToBinding(pointer.scroll(const Offset(150, 60)));
    await tester.pump();
    expect(horizontal.offset, 150);
    expect(vertical.offset, 60);

    // Shift + roda: no Windows e no Linux só o eixo vertical chega no evento.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 90)));
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    expect(horizontal.offset, 240);
    expect(vertical.offset, 60);

    // As setas do teclado percorrem as colunas.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(horizontal.offset, 240 + kColumnScrollStep);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(horizontal.offset, 240);
  });

  testWidgets('a grade só constrói as colunas sob a viewport', (tester) async {
    final wide = await pumpWideGrid(tester);
    final ScrollController horizontal = tester
        .widget<SingleChildScrollView>(
          find.descendant(
            of: find.byType(DataGrid),
            matching: find.byType(SingleChildScrollView),
          ),
        )
        .controller!;

    // No começo da grade, as colunas do fim nem existem na árvore.
    expect(find.text('pedido'), findsOneWidget);
    expect(find.text('Cliente 0'), findsOneWidget);
    expect(find.text('status'), findsNothing);
    expect(find.text('data_pedido'), findsNothing);

    horizontal.jumpTo(horizontal.position.maxScrollExtent);
    await tester.pumpAndSettle();
    // No fim é a vez das primeiras saírem — cabeçalho e células juntos.
    expect(find.text('status'), findsOneWidget);
    expect(find.text('Pago'), findsWidgets);
    expect(find.text('pedido'), findsNothing);
    expect(find.text('Cliente 0'), findsNothing);

    // Ocultar uma coluna troca a lista sob a janela sem necessariamente movê-la.
    horizontal.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('cliente'), findsOneWidget);
    wide.setColumnVisible(1, false);
    await tester.pumpAndSettle();
    expect(find.text('cliente'), findsNothing);
    expect(find.text('Cliente 0'), findsNothing);
    expect(find.text('cidade'), findsOneWidget);
    horizontal.jumpTo(horizontal.position.maxScrollExtent);
    await tester.pumpAndSettle();

    // Alargar uma coluna com a grade rolada mexe na extensão do scroll durante
    // o layout; a janela se reajusta no quadro seguinte, sem quebrar.
    wide.setColumnWidth(0, 900);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('status'), findsOneWidget);
  });

  testWidgets('o botão Fechar volta à tela inicial', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.byType(TextField).last, 'recife');
    controller.toggleInspector();
    await tester.pumpAndSettle();
    expect(controller.visibleRowCount, 2);

    await tester.tap(find.byTooltip('Fechar arquivo (⌘W)'));
    await tester.pumpAndSettle();
    expect(controller.hasDocument, isFalse);
    expect(find.text('Abrir arquivo…'), findsOneWidget);
    expect(find.byType(DataGrid), findsNothing);
    expect(find.text('pedidos.csv'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField).last).controller!.text, isEmpty);
    // Sem documento não há o que fechar: o botão some, como o do painel.
    expect(find.byTooltip('Fechar arquivo (⌘W)'), findsNothing);
    expect(tester.takeException(), isNull);
    await capture(tester, '11-fechado');
  });

  testWidgets('busca rápida filtra e destaca', (tester) async {
    await pumpApp(tester);
    await tester.enterText(find.byType(TextField).last, 'recife');
    await tester.pumpAndSettle();
    expect(controller.visibleRowCount, 2);
    await capture(tester, '06-busca');
  });
}
