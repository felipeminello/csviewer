import 'package:flutter/material.dart';

import '../model/filter.dart';
import '../state/app_controller.dart';
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
              'Filtros',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
          if (filters.isEmpty)
            Text(
              'nenhum — todos os registros estão visíveis',
              style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.45)),
            ),
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
