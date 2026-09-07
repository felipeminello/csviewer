import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_controller.dart';
import 'theme.dart';

/// Side panel showing every field of the selected record — the readable way to
/// inspect a row that is wider than the window.
class RecordInspector extends StatelessWidget {
  const RecordInspector({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final columns = controller.columns;
    final selected = controller.selectedRow;
    final colors = GridColors.of(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(left: BorderSide(color: colors.gridLine)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: kHeaderHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colors.header,
              border: Border(bottom: BorderSide(color: colors.gridLine)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selected == null
                        ? 'Registro'
                        : 'Registro ${(controller.selectedViewIndex ?? 0) + 1} '
                            '· linha ${selected.sourceRow + 1}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  iconSize: 15,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Fechar painel',
                  onPressed: controller.toggleInspector,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Expanded(
            child: selected == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        controller.selectedViewIndex == null
                            ? 'Selecione uma linha para ver todos os campos.'
                            : 'Lendo o registro…',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: onSurface.withValues(alpha: 0.5)),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: columns.length,
                    separatorBuilder: (_, _) => Divider(height: 1, color: colors.gridLine),
                    itemBuilder: (context, index) {
                      final value = selected.cell(index);
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              columns[index].name,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: onSurface.withValues(alpha: 0.55),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: SelectableText(
                                    value.isEmpty ? '—' : value,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                                IconButton(
                                  iconSize: 14,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                  tooltip: 'Copiar valor',
                                  onPressed: value.isEmpty
                                      ? null
                                      : () => Clipboard.setData(ClipboardData(text: value)),
                                  icon: const Icon(Icons.copy),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
