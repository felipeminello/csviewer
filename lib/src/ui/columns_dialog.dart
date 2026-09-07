import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/app_controller.dart';
import 'dialogs.dart';

/// Show / hide columns, the way CSViewer's column chooser works.
class ColumnsDialog extends StatefulWidget {
  const ColumnsDialog({super.key, required this.controller});

  final AppController controller;

  @override
  State<ColumnsDialog> createState() => _ColumnsDialogState();
}

class _ColumnsDialogState extends State<ColumnsDialog> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final columns = widget.controller.columns;
    final needle = _search.toLowerCase();
    final indices = <int>[
      for (var i = 0; i < columns.length; i++)
        if (needle.isEmpty || columns[i].name.toLowerCase().contains(needle)) i,
    ];
    var visible = 0;
    for (var i = 0; i < columns.length; i++) {
      if (widget.controller.isColumnVisible(i)) visible++;
    }
    // A altura vem do arquivo, não da busca: assim a janela não pula de
    // tamanho enquanto se digita, e arquivos estreitos não abrem um vazio.
    final listHeight = math.min(360.0, math.max(132.0, columns.length * 30.0 + 8));

    return AppDialog(
      title: 'Colunas',
      subtitle: '$visible de ${columns.length} visíveis na grade',
      width: 420,
      scrollable: false,
      actions: [
        TextButton(
          onPressed: visible == columns.length
              ? null
              : () => setState(widget.controller.showAllColumns),
          child: const Text('Mostrar todas'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Concluir'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSearchField(
            hintText: 'Buscar coluna…',
            onChanged: (value) => setState(() => _search = value),
          ),
          const SizedBox(height: 12),
          ListPanel(
            height: listHeight,
            child: indices.isEmpty
                ? Center(
                    child: Text(
                      'Nenhuma coluna com esse texto.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: indices.length,
                    itemExtent: 30,
                    itemBuilder: (context, position) {
                      final index = indices[position];
                      return CheckboxListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        value: widget.controller.isColumnVisible(index),
                        title: Text(
                          columns[index].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        onChanged: (value) => setState(
                          () => widget.controller.setColumnVisible(index, value ?? true),
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
