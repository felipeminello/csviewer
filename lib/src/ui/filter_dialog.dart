import 'package:flutter/material.dart';

import '../model/column_meta.dart';
import '../model/filter.dart';
import '../state/app_controller.dart';

/// Editor for a single rule of the filter chain.
class FilterDialog extends StatefulWidget {
  const FilterDialog({
    super.key,
    required this.controller,
    this.initial,
    this.isFirst = true,
  });

  final AppController controller;
  final FilterRule? initial;
  final bool isFirst;

  @override
  State<FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<FilterDialog> {
  late int _column;
  late FilterOp _op;
  late FilterJoin _join;
  late bool _caseSensitive;
  late Set<String> _values;
  final TextEditingController _value = TextEditingController();
  final TextEditingController _value2 = TextEditingController();
  final TextEditingController _valueSearch = TextEditingController();
  List<String>? _distinct;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _column = initial?.column ?? 0;
    _op = initial?.op ?? FilterOp.contains;
    _join = initial?.join ?? FilterJoin.and;
    _caseSensitive = initial?.caseSensitive ?? false;
    _values = Set<String>.from(initial?.values ?? const <String>{});
    _value.text = initial?.value ?? '';
    _value2.text = initial?.value2 ?? '';
    if (_op == FilterOp.inSet) _loadDistinct();
  }

  @override
  void dispose() {
    _value.dispose();
    _value2.dispose();
    _valueSearch.dispose();
    super.dispose();
  }

  void _loadDistinct() {
    _distinct = widget.controller.distinctValues(_column);
  }

  List<FilterOp> get _opsForColumn {
    final meta = widget.controller.table!.columns[_column];
    final common = <FilterOp>[
      FilterOp.contains,
      FilterOp.notContains,
      FilterOp.equals,
      FilterOp.notEquals,
      FilterOp.startsWith,
      FilterOp.endsWith,
      FilterOp.inSet,
      FilterOp.isEmpty,
      FilterOp.isNotEmpty,
      FilterOp.matchesRegex,
    ];
    final comparisons = <FilterOp>[
      FilterOp.greater,
      FilterOp.greaterOrEqual,
      FilterOp.less,
      FilterOp.lessOrEqual,
      FilterOp.between,
    ];
    if (meta.type == ColumnType.text) {
      return [...common, ...comparisons];
    }
    return [
      FilterOp.equals,
      FilterOp.notEquals,
      ...comparisons,
      FilterOp.inSet,
      FilterOp.isEmpty,
      FilterOp.isNotEmpty,
      FilterOp.contains,
      FilterOp.matchesRegex,
    ];
  }

  FilterRule _build() => FilterRule(
        column: _column,
        op: _op,
        value: _value.text,
        value2: _value2.text,
        values: _values,
        caseSensitive: _caseSensitive,
        join: widget.isFirst ? FilterJoin.and : _join,
      );

  bool get _isValid {
    if (_op == FilterOp.inSet) return _values.isNotEmpty;
    if (!_op.needsValue) return true;
    if (_value.text.isEmpty) return false;
    if (_op.needsSecondValue && _value2.text.isEmpty) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final table = widget.controller.table!;
    final ops = _opsForColumn;
    if (!ops.contains(_op)) _op = ops.first;

    return AlertDialog(
      title: Text(widget.initial == null ? 'Novo filtro' : 'Editar filtro'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.isFirst) ...[
                Row(
                  children: [
                    const Text('Combinar com os filtros anteriores usando'),
                    const SizedBox(width: 12),
                    SegmentedButton<FilterJoin>(
                      style: const ButtonStyle(visualDensity: VisualDensity.compact),
                      segments: const [
                        ButtonSegment(value: FilterJoin.and, label: Text('E')),
                        ButtonSegment(value: FilterJoin.or, label: Text('OU')),
                      ],
                      selected: {_join},
                      onSelectionChanged: (s) => setState(() => _join = s.first),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              DropdownButtonFormField<int>(
                initialValue: _column,
                decoration: const InputDecoration(labelText: 'Coluna'),
                isExpanded: true,
                items: [
                  for (var i = 0; i < table.columnCount; i++)
                    DropdownMenuItem(value: i, child: Text(table.columns[i].name)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _column = value;
                    _values = <String>{};
                    _distinct = null;
                    if (_op == FilterOp.inSet) _loadDistinct();
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<FilterOp>(
                initialValue: ops.contains(_op) ? _op : ops.first,
                decoration: const InputDecoration(labelText: 'Condição'),
                isExpanded: true,
                items: [
                  for (final op in ops) DropdownMenuItem(value: op, child: Text(op.label)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _op = value;
                    if (_op == FilterOp.inSet && _distinct == null) _loadDistinct();
                  });
                },
              ),
              const SizedBox(height: 12),
              if (_op == FilterOp.inSet)
                _valuePicker(context)
              else if (_op.needsValue) ...[
                TextField(
                  controller: _value,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: _op.needsSecondValue ? 'De' : 'Valor',
                    hintText: _hintFor(table.columns[_column]),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _submit(),
                ),
                if (_op.needsSecondValue) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _value2,
                    decoration: const InputDecoration(labelText: 'Até'),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _submit(),
                  ),
                ],
              ],
              if (_op != FilterOp.isEmpty && _op != FilterOp.isNotEmpty)
                CheckboxListTile(
                  value: _caseSensitive,
                  onChanged: (v) => setState(() => _caseSensitive = v ?? false),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('Diferenciar maiúsculas de minúsculas'),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _isValid ? _submit : null,
          child: Text(widget.initial == null ? 'Adicionar' : 'Salvar'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_isValid) return;
    Navigator.of(context).pop(_build());
  }

  String? _hintFor(ColumnMeta meta) {
    switch (meta.type) {
      case ColumnType.number:
        return meta.numberStyle == NumberStyle.comma ? 'ex.: 1.234,56' : 'ex.: 1234.56';
      case ColumnType.date:
        return 'ex.: 2024-01-31 ou 31/01/2024';
      case ColumnType.text:
        return null;
    }
  }

  Widget _valuePicker(BuildContext context) {
    final all = _distinct ?? const <String>[];
    final needle = _valueSearch.text.toLowerCase();
    final shown = needle.isEmpty
        ? all
        : all.where((v) => v.toLowerCase().contains(needle)).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _valueSearch,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search, size: 16),
            hintText: 'Buscar valores…',
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('${_values.length} de ${all.length} selecionados',
                style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => _values = Set<String>.from(shown)),
              child: const Text('Marcar visíveis'),
            ),
            TextButton(
              onPressed: () => setState(() => _values = <String>{}),
              child: const Text('Limpar'),
            ),
          ],
        ),
        SizedBox(
          height: 240,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(6),
            child: ListView.builder(
              itemCount: shown.length,
              itemExtent: 30,
              itemBuilder: (context, index) {
                final value = shown[index];
                return CheckboxListTile(
                  value: _values.contains(value),
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    value.isEmpty ? '(vazio)' : value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontStyle: value.isEmpty ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                  onChanged: (checked) => setState(() {
                    if (checked ?? false) {
                      _values.add(value);
                    } else {
                      _values.remove(value);
                    }
                  }),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
