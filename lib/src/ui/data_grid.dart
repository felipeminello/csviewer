import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../data/csv_source.dart';
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

  // Horizontal virtualisation. A wide CSV has hundreds of columns per row, and
  // building every one of them for every row on screen is what makes sideways
  // scrolling crawl. Only the columns under the viewport — plus one on each
  // side, so a partly revealed column is already there — become widgets; the
  // ones to their left are replaced by a single spacer that keeps the rest in
  // place. What is off to the right needs no spacer: the row is stretched to
  // the full content width by the list anyway.
  static const int _overscan = 1;
  List<int> _columns = const [];
  List<int> _window = const [];
  double _leading = 0;
  int _first = 0;
  int _last = 0;
  double _numberWidth = 0;
  double _viewportWidth = 0;

  @override
  void initState() {
    super.initState();
    _horizontal.addListener(_onHorizontalScroll);
  }

  @override
  void dispose() {
    _horizontal.removeListener(_onHorizontalScroll);
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
      case LogicalKeyboardKey.arrowLeft:
        _scrollHorizontally(-kColumnScrollStep);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _scrollHorizontally(kColumnScrollStep);
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

  void _onHorizontalScroll() {
    if (!_updateColumnWindow()) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      // The position also notifies mid-layout, when a resize changes the
      // content width; rebuilding then would be too late for this frame.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  /// Clips the visible columns to the horizontal window. Returns `true` when
  /// the window moved and the grid has to be rebuilt.
  bool _updateColumnWindow() {
    final start = (_horizontal.hasClients ? _horizontal.offset : 0.0) - _numberWidth;
    final end = start + _viewportWidth;
    var first = 0;
    var leading = 0.0;
    while (first < _columns.length) {
      final width = controller.columnWidth(_columns[first]);
      if (leading + width > start) break;
      leading += width;
      first++;
    }
    for (var i = 0; i < _overscan && first > 0; i++) {
      leading -= controller.columnWidth(_columns[--first]);
    }
    var last = first;
    var x = leading;
    while (last < _columns.length && x < end) {
      x += controller.columnWidth(_columns[last]);
      last++;
    }
    for (var i = 0; i < _overscan && last < _columns.length; i++) {
      last++;
    }
    final moved = first != _first || last != _last || leading != _leading;
    _first = first;
    _last = last;
    _leading = leading;
    // Recut even when the window sat still: hiding a column keeps the same
    // slice bounds over a different list of columns.
    _window = _columns.sublist(first, last);
    return moved;
  }

  void _scrollHorizontally(double delta) {
    if (!_horizontal.hasClients) return;
    final position = _horizontal.position;
    _horizontal.jumpTo(
      (position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent),
    );
  }

  /// Wheel and trackpad. Only one scrollable wins a pointer signal, and the
  /// innermost one registers first — that is the vertical list, which reads
  /// just the vertical axis of the gesture and drops the rest, so a sideways
  /// trackpad swipe never reached the grid. The listeners below sit under the
  /// list (on the rows themselves), so they claim the event first and hand
  /// each axis to its own controller.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final (dx, dy) = _pointerScrollDelta(event);
    if (!_canScroll(_horizontal, dx) && !_canScroll(_vertical, dy)) return;
    GestureBinding.instance.pointerSignalResolver.register(event, _applyPointerScroll);
  }

  void _applyPointerScroll(PointerEvent event) {
    final (dx, dy) = _pointerScrollDelta(event as PointerScrollEvent);
    if (_canScroll(_horizontal, dx)) _horizontal.position.pointerScroll(dx);
    if (_canScroll(_vertical, dy)) _vertical.position.pointerScroll(dy);
    event.respond(allowPlatformDefault: false);
  }

  (double, double) _pointerScrollDelta(PointerScrollEvent event) {
    var dx = event.scrollDelta.dx;
    var dy = event.scrollDelta.dy;
    if (HardwareKeyboard.instance.isShiftPressed) {
      // Shift + wheel scrolls sideways. macOS already swaps the axes for us;
      // on Windows and Linux the delta still arrives on the vertical one.
      if (dx == 0) dx = dy;
      dy = 0;
    }
    return (dx, dy);
  }

  bool _canScroll(ScrollController controller, double delta) {
    if (delta == 0 || !controller.hasClients) return false;
    final position = controller.position;
    return delta < 0
        ? position.pixels > position.minScrollExtent
        : position.pixels < position.maxScrollExtent;
  }

  /// Widens a column to fit the longest value currently in view.
  void _autoFit(int column) {
    final style = DefaultTextStyle.of(context).style.copyWith(fontSize: 12.5);
    final painter = TextPainter(textDirection: TextDirection.ltr);
    double widest = _measure(
      painter,
      controller.columns[column].name,
      style.copyWith(fontWeight: FontWeight.w600),
    );
    // Only rows already read are measured — on a huge file that is the window
    // around the viewport, which is exactly what the user is looking at.
    final sample = math.min(controller.visibleRowCount, 800);
    for (var i = 0; i < sample; i++) {
      final row = controller.rowIfReady(i);
      if (row == null) continue;
      final width = _measure(painter, row.cell(column), style);
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
    final columns = controller.visibleColumns;
    final colors = GridColors.of(context);
    // Row numbers reach eight digits on a 25-million-record file.
    final numberWidth = math.max(
      kRowNumberWidth,
      26 + '${controller.visibleRowCount}'.length * 7.5,
    );
    final totalWidth =
        numberWidth + columns.fold<double>(0, (sum, c) => sum + controller.columnWidth(c));

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _viewportHeight = constraints.maxHeight;
          final width = math.max(totalWidth, constraints.maxWidth);
          _columns = columns;
          _numberWidth = numberWidth;
          _viewportWidth = constraints.maxWidth;
          _updateColumnWindow();
          return Scrollbar(
            controller: _vertical,
            // The list scrolls inside the horizontal viewport, so notifications
            // arrive nested; each bar listens to its own axis only.
            notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
            child: Scrollbar(
              controller: _horizontal,
              notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: _horizontal,
                scrollDirection: Axis.horizontal,
                // Covers the header and the empty state, where no row listener
                // is in the hit-test path.
                child: Listener(
                  onPointerSignal: _onPointerSignal,
                  child: SizedBox(
                    width: width,
                    height: constraints.maxHeight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _HeaderRow(
                          controller: controller,
                          columns: _window,
                          colors: colors,
                          numberWidth: numberWidth,
                          leading: _leading,
                          filler: width - totalWidth,
                          onFilterColumn: widget.onFilterColumn,
                          onAutoFit: _autoFit,
                        ),
                        Expanded(
                          child: controller.visibleRowCount == 0
                              ? _EmptyResult(controller: controller)
                              : MouseRegion(
                                  onExit: (_) => setState(() => _hoveredRow = null),
                                  child: ListView.builder(
                                    controller: _vertical,
                                    itemExtent: kRowHeight,
                                    itemCount: controller.visibleRowCount,
                                    itemBuilder: (context, index) => _buildRow(
                                      context,
                                      index,
                                      colors,
                                      numberWidth,
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
            ),
          );
        },
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    int viewIndex,
    GridColors colors,
    double numberWidth,
    double filler,
  ) {
    // Asking as the row is painted is what drives reading from a large file:
    // only the records on screen (plus their window) are ever decoded.
    controller.ensureRange(viewIndex, viewIndex);
    final LoadedRow? row = controller.rowIfReady(viewIndex);
    final selected = controller.selectedViewIndex == viewIndex;
    final hovered = _hoveredRow == viewIndex;
    final Color background = selected
        ? colors.selection
        : hovered
            ? colors.hover
            : (viewIndex.isOdd ? colors.stripe : Colors.transparent);

    return Listener(
      // Sits below the vertical list, so this is what claims the pointer
      // signal and both axes of the gesture survive.
      onPointerSignal: _onPointerSignal,
      child: MouseRegion(
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
                _RowNumber(
                  number: viewIndex + 1,
                  sourceLine: row == null ? null : row.sourceRow + 1,
                  width: numberWidth,
                  colors: colors,
                ),
                // Stands in for every column scrolled off to the left.
                if (_leading > 0) SizedBox(width: _leading),
                for (final c in _window)
                  if (row == null)
                    _PendingCell(width: controller.columnWidth(c), colors: colors)
                  else
                    _Cell(
                      text: row.cell(c),
                      width: controller.columnWidth(c),
                      numeric: controller.columns[c].isNumeric,
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
      ),
    );
  }
}

class _RowNumber extends StatelessWidget {
  const _RowNumber({
    required this.number,
    required this.sourceLine,
    required this.width,
    required this.colors,
  });

  final int number;
  final int? sourceLine;
  final double width;
  final GridColors colors;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: sourceLine == null ? 'Lendo…' : 'Linha $sourceLine do arquivo',
      waitDuration: const Duration(milliseconds: 900),
      child: Container(
        width: width,
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

class _PendingCell extends StatelessWidget {
  const _PendingCell({required this.width, required this.colors});

  final double width;
  final GridColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: kRowHeight,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: colors.gridLine)),
      ),
      child: FractionallySizedBox(
        widthFactor: 0.6,
        alignment: Alignment.centerLeft,
        child: Container(
          height: 8,
          decoration: BoxDecoration(
            color: colors.gridLine,
            borderRadius: BorderRadius.circular(4),
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
    required this.numberWidth,
    required this.leading,
    required this.filler,
    required this.onFilterColumn,
    required this.onAutoFit,
  });

  final AppController controller;
  final List<int> columns;
  final GridColors colors;
  final double numberWidth;
  final double leading;
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
            width: numberWidth,
            height: kHeaderHeight,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(border: Border(right: BorderSide(color: colors.gridLine))),
            child: Icon(Icons.tag,
                size: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
          ),
          if (leading > 0) SizedBox(width: leading),
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
    final meta = controller.columns[column];
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
                ? (controller.indexing
                    ? 'Lendo o arquivo…'
                    : 'O arquivo não tem registros.')
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
