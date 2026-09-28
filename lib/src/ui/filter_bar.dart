import 'package:flutter/material.dart';

import '../model/filter.dart';
import '../state/app_controller.dart';
import 'sort_dialog.dart';
import 'theme.dart';

/// The chain of active filters, shown as chips joined by E / OU.
class FilterBar extends StatelessWidget {
  const FilterBar({super.key, required this.controller, required this.onEdit, required this.onAdd});

  final AppController controller;
  final void Function(int index) onEdit;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final filters = controller.filters;
    final columns = controller.columns;

    return _ViewBar(
      label: 'Filtros',
      emptyText: filters.isEmpty ? 'nenhum — todos os registros estão visíveis' : null,
      children: [
        for (var i = 0; i < filters.length; i++) ...[
          if (i > 0)
            _JoinBadge(
              join: filters[i].join,
              onTap: () => controller.updateFilter(
                i,
                filters[i].copyWith(
                  join: filters[i].join == FilterJoin.and ? FilterJoin.or : FilterJoin.and,
                ),
              ),
            ),
          _FilterChip(
            rule: filters[i],
            label: filters[i].describe(columns),
            onTap: () => onEdit(i),
            onToggle: () => controller.toggleFilterEnabled(i),
            onRemove: () => controller.removeFilter(i),
          ),
        ],
        ActionChip(
          avatar: const Icon(Icons.add, size: 15),
          label: const Text('Adicionar filtro'),
          visualDensity: VisualDensity.compact,
          onPressed: onAdd,
        ),
        if (filters.isNotEmpty)
          TextButton.icon(
            onPressed: controller.clearFilters,
            icon: const Icon(Icons.clear_all, size: 15),
            label: const Text('Limpar tudo'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
      ],
    );
  }
}

/// The sort chain, first key first. It stays on screen even when empty: if it
/// appeared on the first header click, the grid would jump down under the
/// pointer and the second click (to go descending) would miss the header.
class SortBar extends StatelessWidget {
  const SortBar({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final sorts = controller.sorts;
    final columns = controller.columns;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return _ViewBar(
      label: 'Ordenação',
      emptyText: sorts.isEmpty ? 'nenhuma — registros na ordem do arquivo' : null,
      children: [
        for (var i = 0; i < sorts.length; i++) ...[
          if (i > 0)
            Text(
              'depois',
              style: TextStyle(fontSize: 11.5, color: onSurface.withValues(alpha: 0.55)),
            ),
          _SortChip(
            label: _label(sorts, i),
            ascending: sorts[i].ascending,
            onFlip: () => controller.flipSort(sorts[i].column),
            onRemove: () => controller.removeSort(sorts[i].column),
          ),
        ],
        Tooltip(
          message: 'Ou Shift + clique no cabeçalho da coluna',
          child: ActionChip(
            avatar: const Icon(Icons.add, size: 15),
            label: const Text('Adicionar critério'),
            visualDensity: VisualDensity.compact,
            onPressed: sorts.length < columns.length
                ? () => showSortDialog(context, controller, addLevel: true)
                : null,
          ),
        ),
        if (sorts.isNotEmpty) ...[
          // Trocar colunas e mudar a prioridade ficam na janela.
          TextButton.icon(
            onPressed: () => showSortDialog(context, controller),
            icon: const Icon(Icons.low_priority, size: 15),
            label: const Text('Editar…'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
          TextButton.icon(
            onPressed: controller.clearSort,
            icon: const Icon(Icons.clear_all, size: 15),
            label: const Text('Limpar'),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          ),
        ],
      ],
    );
  }

  String _label(List<SortSpec> sorts, int index) {
    final meta = controller.columns[sorts[index].column];
    // Numerado como no cabeçalho quando há mais de um critério.
    final number = sorts.length > 1 ? '${index + 1}. ' : '';
    return '$number${meta.name} (${directionLabel(meta, ascending: sorts[index].ascending)})';
  }
}

/// Faixa comum às barras de filtros e de ordenação: rótulo à esquerda e os
/// chips quebrando linha quando não cabem.
class _ViewBar extends StatelessWidget {
  const _ViewBar({required this.label, required this.children, this.emptyText});

  final String label;
  final String? emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: Border(bottom: BorderSide(color: GridColors.of(context).gridLine)),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
          if (emptyText != null)
            Text(
              emptyText!,
              style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.45)),
            ),
          ...children,
        ],
      ),
    );
  }
}

class _JoinBadge extends StatelessWidget {
  const _JoinBadge({required this.join, required this.onTap});

  final FilterJoin join;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isAnd = join == FilterJoin.and;
    return Tooltip(
      message: isAnd
          ? 'E — o registro precisa passar também neste filtro (clique para trocar por OU)'
          : 'OU — inicia um novo grupo de condições (clique para trocar por E)',
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Text(
            isAnd ? 'E' : 'OU',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isAnd ? AppTheme.accent : Colors.orange.shade800,
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.rule,
    required this.label,
    required this.onTap,
    required this.onToggle,
    required this.onRemove,
  });

  final FilterRule rule;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final enabled = rule.enabled;
    return InputChip(
      visualDensity: VisualDensity.compact,
      isEnabled: true,
      avatar: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        iconSize: 15,
        tooltip: enabled ? 'Desativar filtro' : 'Ativar filtro',
        icon: Icon(enabled ? Icons.check_circle : Icons.radio_button_unchecked),
        color: enabled ? AppTheme.accent : null,
        onPressed: onToggle,
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          decoration: enabled ? null : TextDecoration.lineThrough,
        ),
      ),
      onPressed: onTap,
      onDeleted: onRemove,
      deleteIcon: const Icon(Icons.close, size: 15),
      tooltip: 'Clique para editar',
    );
  }
}

/// Clicar em qualquer ponto do chip inverte a direção. Um botão próprio no
/// avatar não serviria: o chip entrega ao rótulo todo toque fora do "x".
class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.ascending,
    required this.onFlip,
    required this.onRemove,
  });

  final String label;
  final bool ascending;
  final VoidCallback onFlip;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(
        ascending ? Icons.arrow_upward : Icons.arrow_downward,
        size: 15,
        color: AppTheme.accent,
      ),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      onPressed: onFlip,
      onDeleted: onRemove,
      deleteIcon: const Icon(Icons.close, size: 15),
      tooltip: 'Clique para inverter a direção',
    );
  }
}
