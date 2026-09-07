import 'package:flutter/material.dart';

import '../state/app_controller.dart';

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

    return AlertDialog(
      title: const Text('Colunas'),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: 380,
        height: 420,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 16),
                hintText: 'Buscar coluna…',
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: indices.length,
                itemExtent: 36,
                itemBuilder: (context, position) {
                  final index = indices[position];
                  return CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
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
      ),
      actions: [
        TextButton(
          onPressed: () => setState(widget.controller.showAllColumns),
          child: const Text('Mostrar todas'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Concluir'),
        ),
      ],
    );
  }
}
