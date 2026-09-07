import 'package:flutter/material.dart';

import '../services/csv_parser.dart';
import '../state/app_controller.dart';
import 'theme.dart';

class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final colors = GridColors.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65);
    final shown = controller.visibleRowCount;
    final total = controller.totalRows;
    final hiddenColumns = controller.columnCount - controller.visibleColumns.length;
    final indexing = controller.indexing;
    final busy = controller.busy;

    return Container(
      decoration: BoxDecoration(
        color: colors.header,
        border: Border(top: BorderSide(color: colors.gridLine)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reading or scanning a multi-gigabyte file takes time; show it.
          SizedBox(
            height: 2,
            child: indexing || busy
                ? LinearProgressIndicator(
                    minHeight: 2,
                    value: indexing ? controller.indexProgress : controller.busyProgress,
                  )
                : null,
          ),
          SizedBox(
            height: 24,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: DefaultTextStyle.merge(
                style: TextStyle(fontSize: 11.5, color: onSurface),
                child: Row(
                  children: [
                    Text(
                      shown == total
                          ? '${_number(total)} registros${indexing ? '…' : ''}'
                          : '${_number(shown)} de ${_number(total)} registros${indexing ? '…' : ''}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: onSurface,
                        fontWeight: shown == total ? FontWeight.w400 : FontWeight.w600,
                      ),
                    ),
                    _dot(),
                    Text('${controller.columnCount} colunas'
                        '${hiddenColumns > 0 ? ' ($hiddenColumns oculta${hiddenColumns > 1 ? 's' : ''})' : ''}'),
                    if (controller.sorts.isNotEmpty) ...[
                      _dot(),
                      Text(controller.sorts
                          .map((s) =>
                              '${controller.columns[s.column].name} ${s.ascending ? '↑' : '↓'}')
                          .join(', ')),
                    ],
                    if (indexing) ...[
                      _dot(),
                      Text('Indexando ${(controller.indexProgress * 100).round()}%'),
                    ] else if (busy) ...[
                      _dot(),
                      Text('Filtrando ${(controller.busyProgress * 100).round()}%'),
                    ],
                    const Spacer(),
                    Tooltip(
                      message: controller.isStreaming
                          ? 'Arquivo grande: lido do disco sob demanda, sem carregar tudo na memória'
                          : 'Arquivo carregado inteiramente na memória',
                      child: Text(controller.isStreaming ? 'streaming' : 'memória'),
                    ),
                    _dot(),
                    Text(delimiterLabel(controller.delimiter)),
                    _dot(),
                    Text(controller.encodingName),
                    _dot(),
                    Text(_size(controller.fileSizeBytes)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot() => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Text('·'),
      );

  static String _number(int value) {
    final text = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) buffer.write('.');
      buffer.write(text[i]);
    }
    return buffer.toString();
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
