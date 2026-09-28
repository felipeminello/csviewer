import 'package:flutter/material.dart';

import '../model/column_meta.dart';
import '../state/app_controller.dart';
import 'dialogs.dart';

/// Abre o editor da ordenação e aplica o resultado. Com [addLevel] a janela
/// já abre com um critério novo no fim, pronto para escolher a coluna; com
/// [column] (vindo do cabeçalho) esse critério novo é essa coluna, a menos que
/// ela já esteja na ordenação.
Future<void> showSortDialog(
  BuildContext context,
  AppController controller, {
  bool addLevel = false,
  int? column,
}) async {
  if (!controller.hasDocument) return;
  final result = await showDialog<List<SortSpec>>(
    context: context,
    builder: (context) => SortDialog(controller: controller, addLevel: addLevel, column: column),
  );
  if (result != null) controller.setSorts(result);
}

/// Cadeia de ordenação: o primeiro critério manda, os seguintes só desempatam
/// os registros que ficaram iguais nos anteriores.
class SortDialog extends StatefulWidget {
  const SortDialog({super.key, required this.controller, this.addLevel = false, this.column});

  final AppController controller;
  final bool addLevel;
  final int? column;

  @override
  State<SortDialog> createState() => _SortDialogState();
}

class _Level {
  _Level(this.column, this.ascending) : id = _nextId++;

  static int _nextId = 0;

  /// Chave estável da linha: ao subir ou descer um critério, o campo de
  /// seleção vai junto com ele em vez de herdar o valor do vizinho.
  final int id;
  int column;
  bool ascending;
}

class _SortDialogState extends State<SortDialog> {
  late final List<_Level> _levels;

  List<ColumnMeta> get _columns => widget.controller.columns;

  @override
  void initState() {
    super.initState();
    _levels = [for (final spec in widget.controller.sorts) _Level(spec.column, spec.ascending)];
    final wanted = widget.column;
    if (wanted != null && !_levels.any((level) => level.column == wanted)) {
      _levels.add(_Level(wanted, true));
    } else if (widget.addLevel || _levels.isEmpty) {
      _addLevel();
    }
  }

  int? get _firstUnusedColumn {
    final used = {for (final level in _levels) level.column};
    for (var i = 0; i < _columns.length; i++) {
      if (!used.contains(i)) return i;
    }
    return null;
  }

  void _addLevel() {
    final column = _firstUnusedColumn;
    if (column != null) _levels.add(_Level(column, true));
  }

  List<SortSpec> get _result => [
    for (final level in _levels) SortSpec(level.column, ascending: level.ascending),
  ];

  void _move(int index, int delta) {
    setState(() {
      final level = _levels.removeAt(index);
      _levels.insert(index + delta, level);
    });
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return AppDialog(
      title: 'Ordenar por colunas',
      subtitle: 'O primeiro critério ordena os registros; os seguintes desempatam os iguais.',
      width: 560,
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_result),
          child: const Text('Aplicar'),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_levels.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Sem ordenação — os registros aparecem na ordem do arquivo.',
                style: TextStyle(fontSize: 13, color: onSurface.withValues(alpha: 0.6)),
              ),
            ),
          for (var i = 0; i < _levels.length; i++) ...[
            if (i > 0) const SizedBox(height: kFieldGap),
            _levelRow(i),
          ],
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _firstUnusedColumn == null ? null : () => setState(_addLevel),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Adicionar critério'),
          ),
        ],
      ),
    );
  }

  Widget _levelRow(int index) {
    final level = _levels[index];
    final usedElsewhere = {
      for (final other in _levels)
        if (other != level) other.column,
    };
    final meta = _columns[level.column];

    return Row(
      key: ValueKey(level.id),
      children: [
        Expanded(
          flex: 3,
          child: AppSelect<int>(
            label: index == 0 ? 'Ordenar por' : 'Depois por',
            value: level.column,
            items: [
              for (var c = 0; c < _columns.length; c++)
                if (!usedElsewhere.contains(c))
                  DropdownMenuItem(
                    value: c,
                    child: Text(_columns[c].name, overflow: TextOverflow.ellipsis),
                  ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => level.column = value);
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: AppSelect<bool>(
            label: 'Direção',
            value: level.ascending,
            items: [
              for (final ascending in const [true, false])
                DropdownMenuItem(
                  value: ascending,
                  child: Text(
                    directionLabel(meta, ascending: ascending),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => level.ascending = value);
            },
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          tooltip: 'Aumentar a prioridade',
          onPressed: index == 0 ? null : () => _move(index, -1),
          icon: const Icon(Icons.keyboard_arrow_up),
        ),
        IconButton(
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          tooltip: 'Diminuir a prioridade',
          onPressed: index == _levels.length - 1 ? null : () => _move(index, 1),
          icon: const Icon(Icons.keyboard_arrow_down),
        ),
        IconButton(
          iconSize: 18,
          visualDensity: VisualDensity.compact,
          tooltip: 'Remover critério',
          onPressed: () => setState(() => _levels.removeAt(index)),
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

/// Direção nos termos do tipo da coluna: "A → Z" não diz nada sobre datas.
String directionLabel(ColumnMeta meta, {required bool ascending}) {
  switch (meta.type) {
    case ColumnType.number:
      return ascending ? 'Menor → maior' : 'Maior → menor';
    case ColumnType.date:
      return ascending ? 'Mais antiga → recente' : 'Mais recente → antiga';
    case ColumnType.text:
      return ascending ? 'A → Z' : 'Z → A';
  }
}
