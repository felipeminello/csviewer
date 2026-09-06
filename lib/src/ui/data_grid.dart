import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/column_meta.dart';
import '../state/app_controller.dart';
import 'theme.dart';

typedef ColumnFilterRequest = void Function(int column, {bool byValues});

/// Virtualised CSV grid: sticky header, resizable columns, click-to-sort.
class DataGrid extends StatefulWidget {
  const DataGrid({
    super.key,
    required this.controller,
    required this.onFilterColumn,
  });

  final AppController controller;
  final ColumnFilterRequest onFilterColumn;

  @override
  State<DataGrid> createState() => _DataGridState();
}

class _DataGridState extends State<DataGrid> {
  final ScrollController _vertical = ScrollController();
  final ScrollController _horizontal = ScrollController();
  final FocusNode _focusNode = FocusNode();
  int? _hoveredRow;
  double _viewportHeight = 0;

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  AppController get controller => widget.controller;

  void _moveSelection(int delta, {bool toEdge = false}) {
    final count = controller.visibleRowCount;
    if (count == 0) return;
    final current = controller.selectedViewIndex ?? -1;
    int next;
    if (toEdge) {
      next = delta < 0 ? 0 : count - 1;
    } else {
      next = (current < 0 ? 0 : current + delta).clamp(0, count - 1);
    }
    controller.selectViewRow(next);
    _scrollIntoView(next);
  }

  void _scrollIntoView(int index) {
    if (!_vertical.hasClients) return;
    final top = index * kRowHeight;
    final offset = _vertical.offset;
    final viewport = _viewportHeight - kHeaderHeight;
    if (top < offset) {
      _vertical.jumpTo(math.max(0, top));
    } else if (top + kRowHeight > offset + viewport) {
      _vertical.jumpTo(math.min(_vertical.position.maxScrollExtent, top - viewport + kRowHeight));
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final rowsPerPage = math.max(1, ((_viewportHeight - kHeaderHeight) / kRowHeight).floor() - 1);
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _moveSelection(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _moveSelection(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.pageDown:
        _moveSelection(rowsPerPage);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.pageUp:
        _moveSelection(-rowsPerPage);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        _moveSelection(-1, toEdge: true);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        _moveSelection(1, toEdge: true);
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Widens a column to fit the longest value currently in view.
  void _autoFit(int column) {
    final table = controller.table!;
    final style = DefaultTextStyle.of(context).style.copyWith(fontSize: 12.5);
    final painter = TextPainter(textDirection: TextDirection.ltr);
    double widest = _measure(painter, table.columns[column].name, style.copyWith(fontWeight: FontWeight.w600));
    final rows = controller.viewRows;
    final sample = math.min(rows.length, 800);
    for (var i = 0; i < sample; i++) {
      final width = _measure(painter, table.cell(rows[i], column), style);
      if (width > widest) widest = width;
    }
    controller.setColumnWidth(column, widest + 40);
  }

  double _measure(TextPainter painter, String text, TextStyle style) {
    painter
      ..text = TextSpan(text: text, style: style)
      ..layout();
    return painter.width;
  }

  @override
  Widget build(BuildContext context) {
    final table = controller.table!;
    final columns = controller.visibleColumns;
    final colors = GridColors.of(context);
    final totalWidth = kRowNumberWidth +
        columns.fold<double>(0, (sum, c) => sum + controller.columnWidth(c));

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _viewportHeight = constraints.maxHeight;
          final width = math.max(totalWidth, constraints.maxWidth);
          return Scrollbar(
            controller: _vertical,
            notificationPredicate: (_) => true,
            child: Scrollbar(
              controller: _horizontal,
              notificationPredicate: (_) => true,
              child: SingleChildScrollView(
                controller: _horizontal,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  height: constraints.maxHeight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HeaderRow(
                        controller: controller,
                        columns: columns,
                        colors: colors,
                        filler: width - totalWidth,
                        onFilterColumn: widget.onFilterColumn,
                        onAutoFit: _autoFit,
                      ),
                      Expanded(
                        child: controller.viewRows.isEmpty
                            ? _EmptyResult(controller: controller)
                            : MouseRegion(
                                onExit: (_) => setState(() => _hoveredRow = null),
                                child: ListView.builder(
                                  controller: _vertical,
                                  itemExtent: kRowHeight,
                                  itemCount: controller.viewRows.length,
                                  itemBuilder: (context, index) => _buildRow(
                                    context,
                                    index,
                                    table.rows,
                                    columns,
                                    colors,
                                    width - totalWidth,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    int viewIndex,
    List<List<String>> rows,
    List<int> columns,
    GridColors colors,
    double filler,
  ) {
    final table = controller.table!;
    final rowIndex = controller.viewRows[viewIndex];
    final row = rows[rowIndex];
    final selected = controller.selectedViewIndex == viewIndex;
    final hovered = _hoveredRow == viewIndex;
    final Color background = selected
        ? colors.selection
        : hovered
            ? colors.hover
            : (viewIndex.isOdd ? colors.stripe : Colors.transparent);

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredRow = viewIndex),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _focusNode.requestFocus();
          controller.selectViewRow(viewIndex);
        },
        child: Container(
          color: background,
          child: Row(
            children: [
              _RowNumber(number: viewIndex + 1, sourceLine: rowIndex + 1, colors: colors),
              for (final c in columns)
                _Cell(
                  text: c < row.length ? row[c] : '',
                  width: controller.columnWidth(c),
                  numeric: table.columns[c].isNumeric,
                  highlight: controller.quickSearch,
                  colors: colors,
                ),
              // Keeps stripes and the selection highlight running to the edge
              // when the columns do not fill the window.
              if (filler > 0) SizedBox(width: filler),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowNumber extends StatelessWidget {
  const _RowNumber({required this.number, required this.sourceLine, required this.colors});

  final int number;
  final int sourceLine;
  final GridColors colors;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Linha $sourceLine do arquivo',
      waitDuration: const Duration(milliseconds: 900),
      child: Container(
        width: kRowNumberWidth,
        height: kRowHeight,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: colors.gridLine)),
        ),
        child: Text(
          '$number',
          style: TextStyle(
            fontSize: 11.5,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.text,
    required this.width,
    required this.numeric,
    required this.highlight,
    required this.colors,
  });

  final String text;
  final double width;
  final bool numeric;
  final String highlight;
  final GridColors colors;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 12.5,
      color: Theme.of(context).colorScheme.onSurface,
      fontFeatures: numeric ? const [FontFeature.tabularFigures()] : null,
    );
    return Container(
      width: width,
      height: kRowHeight,
      alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: colors.gridLine)),
      ),
      child: _highlighted(context, style),
    );
  }

  Widget _highlighted(BuildContext context, TextStyle style) {
    if (highlight.isEmpty) {
      return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }
    final lower = text.toLowerCase();
    final needle = highlight.toLowerCase();
    final start = lower.indexOf(needle);
    if (start < 0) {
      return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    }
    final marker = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF7A5A00)
        : const Color(0xFFFFE08A);
    final spans = <TextSpan>[];
    var index = 0;
    while (index < text.length) {
      final match = lower.indexOf(needle, index);
      if (match < 0) {
        spans.add(TextSpan(text: text.substring(index)));
        break;
      }
      if (match > index) spans.add(TextSpan(text: text.substring(index, match)));
      spans.add(TextSpan(
        text: text.substring(match, match + needle.length),
        style: TextStyle(backgroundColor: marker),
      ));
      index = match + needle.length;
    }
    // Text.rich (not RichText) so the cell keeps the ambient font.
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.controller,
    required this.columns,
    required this.colors,
    required this.filler,
    required this.onFilterColumn,
    required this.onAutoFit,
  });

  final AppController controller;
  final List<int> columns;
  final GridColors colors;
  final double filler;
  final ColumnFilterRequest onFilterColumn;
  final void Function(int column) onAutoFit;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: kHeaderHeight,
      decoration: BoxDecoration(
        color: colors.header,
        border: Border(bottom: BorderSide(color: colors.gridLine)),
      ),
      child: Row(
        children: [
          Container(
            width: kRowNumberWidth,
            height: kHeaderHeight,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(border: Border(right: BorderSide(color: colors.gridLine))),
            child: Icon(Icons.tag,
                size: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
          ),
          for (final c in columns)
            _HeaderCell(
              controller: controller,
              column: c,
              colors: colors,
              onFilterColumn: onFilterColumn,
              onAutoFit: onAutoFit,
            ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.controller,
    required this.column,
    required this.colors,
    required this.onFilterColumn,
    required this.onAutoFit,
  });

  final AppController controller;
  final int column;
  final GridColors colors;
  final ColumnFilterRequest onFilterColumn;
  final void Function(int column) onAutoFit;

  @override
  Widget build(BuildContext context) {
    final meta = controller.table!.columns[column];
    final sort = controller.sortFor(column);
    final priority = controller.sortPriority(column);
    final width = controller.columnWidth(column);
    final filtered = controller.filters.any((f) => f.enabled && f.column == column);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return SizedBox(
      width: width,
      height: kHeaderHeight,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => controller.toggleSort(
                column,
                additive: HardwareKeyboard.instance.isShiftPressed,
              ),
              onSecondaryTapUp: (details) => _showMenu(context, details.globalPosition),
              onLongPressStart: (details) => _showMenu(context, details.globalPosition),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border(right: BorderSide(color: colors.gridLine)),
                ),
                child: Row(
                  children: [
                    if (filtered)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(Icons.filter_alt, size: 12, color: AppTheme.accent),
                      ),
                    Expanded(
                      child: Text(
                        meta.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: meta.isNumeric ? TextAlign.right : TextAlign.left,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (sort != null) ...[
                      Icon(
                        sort.ascending ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 12,
                        color: AppTheme.accent,
                      ),
                      if (controller.sorts.length > 1)
                        Text(
                          '${priority + 1}',
                          style: const TextStyle(fontSize: 9, color: AppTheme.accent),
                        ),
                    ],
                    Tooltip(
                      message: _typeLabel(meta),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          _typeIcon(meta),
                          size: 11,
                          color: onSurface.withValues(alpha: 0.28),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            width: 8,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) =>
                    controller.setColumnWidth(column, width + details.delta.dx),
                onDoubleTap: () => onAutoFit(column),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _typeIcon(ColumnMeta meta) {
    switch (meta.type) {
      case ColumnType.number:
        return Icons.numbers;
      case ColumnType.date:
        return Icons.event;
      case ColumnType.text:
        return Icons.abc;
    }
  }

  String _typeLabel(ColumnMeta meta) {
    switch (meta.type) {
      case ColumnType.number:
        return 'Coluna numérica';
      case ColumnType.date:
        return 'Coluna de data';
      case ColumnType.text:
        return 'Coluna de texto';
    }
  }

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final selection = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: const [
        PopupMenuItem(value: 'asc', child: Text('Ordenar crescente (A → Z)')),
        PopupMenuItem(value: 'desc', child: Text('Ordenar decrescente (Z → A)')),
        PopupMenuItem(value: 'clearSort', child: Text('Remover ordenação')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'filterValues', child: Text('Filtrar por valores…')),
        PopupMenuItem(value: 'filter', child: Text('Adicionar filtro…')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'autofit', child: Text('Ajustar largura ao conteúdo')),
        PopupMenuItem(value: 'hide', child: Text('Ocultar coluna')),
      ],
    );
    switch (selection) {
      case 'asc':
        controller.setSort(column, true);
        break;
      case 'desc':
        controller.setSort(column, false);
        break;
      case 'clearSort':
        controller.clearSort();
        break;
      case 'filterValues':
        onFilterColumn(column, byValues: true);
        break;
      case 'filter':
        onFilterColumn(column, byValues: false);
        break;
      case 'autofit':
        onAutoFit(column);
        break;
      case 'hide':
        controller.setColumnVisible(column, false);
        break;
    }
  }
}

class _EmptyResult extends StatelessWidget {
  const _EmptyResult({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_alt_off, size: 32, color: onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: 8),
          Text(
            controller.totalRows == 0
                ? 'O arquivo não tem registros.'
                : 'Nenhum registro corresponde aos filtros.',
            style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
          ),
          if (controller.isFiltered) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: controller.clearFilters,
              icon: const Icon(Icons.clear_all, size: 16),
              label: const Text('Limpar filtros'),
            ),
          ],
        ],
      ),
    );
  }
}
