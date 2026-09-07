// Benchmark manual do modo streaming em um arquivo de vários GB.
//
//   python3 tool/gerar_grande.py build/gigante.csv 250   # ~2,5 GB
//   flutter test tool/benchmark_grande.dart
//
// Use CSVIEWER_BIG_FILE para apontar outro arquivo.
import 'dart:io';

import 'package:csviewer/src/data/csv_source.dart';
import 'package:csviewer/src/model/filter.dart';
import 'package:csviewer/src/model/sort_spec.dart';
import 'package:csviewer/src/services/csv_loader.dart';
import 'package:flutter_test/flutter_test.dart';

String _mb(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
String _rss() => _mb(ProcessInfo.currentRss);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('arquivo grande em modo streaming', () async {
    final path = Platform.environment['CSVIEWER_BIG_FILE'] ?? 'build/gigante.csv';
    final file = File(path);
    if (!file.existsSync()) {
      // ignore: avoid_print
      print('arquivo $path não encontrado — gere com tool/gerar_grande.py');
      return;
    }
    final size = file.lengthSync();
    // ignore: avoid_print
    print('arquivo: ${_mb(size)} · RSS inicial ${_rss()}');

    final watch = Stopwatch()..start();
    final source = await openCsvSource(path, const LoadOptions(mode: ReadMode.streaming));
    final openMs = watch.elapsedMilliseconds;
    while (source.indexing) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    // ignore: avoid_print
    print('abriu em ${openMs}ms · indexou ${source.totalRows} registros em '
        '${watch.elapsedMilliseconds}ms · RSS ${_rss()}');

    for (final position in [0, source.totalRows ~/ 2, source.totalRows - 1]) {
      final read = Stopwatch()..start();
      final row = await source.rowAt(position);
      // ignore: avoid_print
      print('registro $position em ${read.elapsedMilliseconds}ms: ${row!.values.take(3).join(' | ')}');
    }
    // ignore: avoid_print
    print('RSS depois de navegar: ${_rss()}');

    watch.reset();
    var result = await source.applyView(
      [FilterRule(column: 2, op: FilterOp.equals, value: 'Recife')],
      '',
      const [],
    );
    // ignore: avoid_print
    print('filtro: ${result.rowCount} registros em ${watch.elapsedMilliseconds}ms · RSS ${_rss()}');

    watch.reset();
    result = await source.applyView(
      [FilterRule(column: 2, op: FilterOp.equals, value: 'Recife')],
      '',
      const [SortSpec(5, ascending: false)],
    );
    // ignore: avoid_print
    print('filtro + ordenação: aplicada=${result.sortApplied} em '
        '${watch.elapsedMilliseconds}ms · RSS ${_rss()}');

    watch.reset();
    result = await source.applyView(
      [
        FilterRule(column: 2, op: FilterOp.equals, value: 'Recife'),
        FilterRule(column: 7, op: FilterOp.equals, value: 'Pago'),
        FilterRule(column: 4, op: FilterOp.greater, value: '18'),
      ],
      '',
      const [SortSpec(5, ascending: false)],
    );
    // ignore: avoid_print
    print('3 filtros + ordenação: ${result.rowCount} registros, aplicada=${result.sortApplied}, '
        '${watch.elapsedMilliseconds}ms · RSS ${_rss()}');
    if (result.sortApplied && result.rowCount > 1) {
      final first = (await source.rowAt(0))!.cell(5);
      final second = (await source.rowAt(1))!.cell(5);
      // ignore: avoid_print
      print('topo ordenado: $first, $second');
    }

    watch.reset();
    final out = '${Directory.systemTemp.path}/csviewer_export.csv';
    final rows = await source.exportTo(out, [0, 1, 2, 5, 7]);
    // ignore: avoid_print
    print('exportou $rows registros em ${watch.elapsedMilliseconds}ms '
        '(${_mb(File(out).lengthSync())}) · RSS ${_rss()}');
    File(out).deleteSync();

    // ignore: avoid_print
    print('RSS final: ${_rss()}');
    source.dispose();
  }, timeout: const Timeout(Duration(minutes: 20)));
}
