import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart' as fs;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../model/filter.dart';
import '../services/csv_loader.dart';
import '../services/csv_parser.dart';
import '../state/app_controller.dart';
import 'columns_dialog.dart';
import 'data_grid.dart';
import 'filter_bar.dart';
import 'filter_dialog.dart';
import 'inspector.dart';
import 'status_bar.dart';
import 'theme.dart';

const fs.XTypeGroup _csvTypeGroup = fs.XTypeGroup(
  label: 'CSV / texto delimitado',
  extensions: <String>['csv', 'tsv', 'txt', 'tab', 'psv'],
);

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomePage> createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _dragging = false;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (_search.text != controller.quickSearch) {
      _search.text = controller.quickSearch;
    }
  }

  // -------------------------------------------------------------- commands

  Future<void> openFile() async {
    final file = await fs.openFile(acceptedTypeGroups: const <fs.XTypeGroup>[_csvTypeGroup]);
    if (file == null) return;
    await controller.openPath(file.path);
    _reportError();
  }

  Future<void> reloadFile() async {
    if (!controller.hasDocument) return;
    await controller.reload(controller.options);
    _reportError();
  }

  Future<void> exportView() async {
    if (!controller.hasDocument) return;
    final suggestion = controller.fileName.replaceAll(RegExp(r'\.[^.]*$'), '');
    final location = await fs.getSaveLocation(
      suggestedName: '$suggestion-filtrado.csv',
      acceptedTypeGroups: const <fs.XTypeGroup>[_csvTypeGroup],
    );
    if (location == null) return;
    try {
      final rows = await controller.export(location.path);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$rows registros exportados para ${location.path.split('/').last}'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Falha ao exportar: $e')),
      );
    }
  }

  void focusSearch() {
    if (!controller.hasDocument) return;
    _searchFocus.requestFocus();
    _search.selection = TextSelection(baseOffset: 0, extentOffset: _search.text.length);
  }

  void copySelectedRow() {
    final row = controller.selectedRow;
    if (row == null) return;
    final text = controller.visibleColumns.map(row.cell).join('\t');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Registro copiado'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> addFilter({int? column, bool byValues = false}) async {
    if (!controller.hasDocument) return;
    final initial = column == null
        ? null
        : FilterRule(
            column: column,
            op: byValues ? FilterOp.inSet : FilterOp.contains,
          );
    final rule = await showDialog<FilterRule>(
      context: context,
      builder: (context) => FilterDialog(
        controller: controller,
        initial: initial,
        isFirst: controller.filters.isEmpty,
      ),
    );
    if (rule != null) controller.addFilter(rule);
  }

  Future<void> _editFilter(int index) async {
    final rule = await showDialog<FilterRule>(
      context: context,
      builder: (context) => FilterDialog(
        controller: controller,
        initial: controller.filters[index],
        isFirst: index == 0,
      ),
    );
    if (rule != null) controller.updateFilter(index, rule);
  }

  Future<void> showColumnsDialog() async {
    if (!controller.hasDocument) return;
    await showDialog<void>(
      context: context,
      builder: (context) => ColumnsDialog(controller: controller),
    );
  }

  Future<void> showReadOptions() async {
    if (!controller.hasDocument) return;
    final result = await showDialog<LoadOptions>(
      context: context,
      builder: (context) => _ReadOptionsDialog(controller: controller),
    );
    if (result == null) return;
    await controller.reload(result);
    _reportError();
  }

  void _reportError() {
    final error = controller.error;
    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _handleDrop(DropDoneDetails details) async {
    if (details.files.isEmpty) return;
    await controller.openPath(details.files.first.path);
    _reportError();
  }

  // ------------------------------------------------------------------ view

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final notice = controller.notice;
        if (notice != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || controller.notice != notice) return;
            controller.clearNotice();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(notice), duration: const Duration(seconds: 6)),
            );
          });
        }
        return DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (details) {
            setState(() => _dragging = false);
            _handleDrop(details);
          },
          child: Scaffold(
            body: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Toolbar(
                      controller: controller,
                      search: _search,
                      searchFocus: _searchFocus,
                      onOpen: openFile,
                      onReload: reloadFile,
                      onExport: exportView,
                      onAddFilter: () => addFilter(),
                      onColumns: showColumnsDialog,
                      onOptions: showReadOptions,
                    ),
                    if (controller.hasDocument)
                      FilterBar(
                        controller: controller,
                        onEdit: _editFilter,
                        onAdd: () => addFilter(),
                      ),
                    Expanded(
                      child: controller.hasDocument
                          ? Row(
                              children: [
                                Expanded(
                                  child: DataGrid(
                                    controller: controller,
                                    onFilterColumn: (column, {bool byValues = false}) =>
                                        addFilter(column: column, byValues: byValues),
                                  ),
                                ),
                                if (controller.showInspector)
                                  RecordInspector(controller: controller),
                              ],
                            )
                          : _WelcomeView(onOpen: openFile),
                    ),
                    if (controller.hasDocument) StatusBar(controller: controller),
                  ],
                ),
                if (controller.loading)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x66000000),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                if (_dragging)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        color: AppTheme.accent.withValues(alpha: 0.12),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppTheme.accent, width: 2),
                            ),
                            child: const Text('Solte o arquivo CSV para abrir'),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.search,
    required this.searchFocus,
    required this.onOpen,
    required this.onReload,
    required this.onExport,
    required this.onAddFilter,
    required this.onColumns,
    required this.onOptions,
  });

  final AppController controller;
  final TextEditingController search;
  final FocusNode searchFocus;
  final VoidCallback onOpen;
  final VoidCallback onReload;
  final VoidCallback onExport;
  final VoidCallback onAddFilter;
  final VoidCallback onColumns;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final hasDocument = controller.hasDocument;
    final colors = GridColors.of(context);

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.header,
        border: Border(bottom: BorderSide(color: colors.gridLine)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Narrow windows drop the button labels and the file name before
          // anything is allowed to overflow.
          final compact = constraints.maxWidth < 940;
          final searchWidth = constraints.maxWidth < 620 ? 150.0 : 240.0;
          return Row(
            children: [
              // The button cluster scrolls rather than overflowing when the
              // window (or the system font) is bigger than expected.
              Flexible(
                flex: 3,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
              _ToolButton(
                icon: Icons.folder_open,
                label: 'Abrir',
                compact: compact,
                onPressed: onOpen,
              ),
              _ToolButton(
                icon: Icons.refresh,
                label: 'Recarregar',
                compact: compact,
                onPressed: hasDocument ? onReload : null,
              ),
              _ToolButton(
                icon: Icons.filter_alt,
                label: 'Filtro',
                tooltip: 'Adicionar filtro (⌘L)',
                compact: compact,
                onPressed: hasDocument ? onAddFilter : null,
              ),
              _ToolButton(
                icon: Icons.view_column,
                label: 'Colunas',
                compact: compact,
                onPressed: hasDocument ? onColumns : null,
              ),
              _ToolButton(
                icon: Icons.tune,
                label: 'Leitura',
                tooltip: 'Delimitador, codificação e cabeçalho',
                compact: compact,
                onPressed: hasDocument ? onOptions : null,
              ),
              _ToolButton(
                icon: Icons.ios_share,
                label: 'Exportar',
                tooltip: 'Salvar a visão atual (filtrada e ordenada) como CSV',
                compact: compact,
                onPressed: hasDocument ? onExport : null,
              ),
              if (hasDocument)
                IconButton(
                  iconSize: 18,
                  tooltip: 'Painel do registro (⌘I)',
                  isSelected: controller.showInspector,
                  onPressed: controller.toggleInspector,
                  icon: const Icon(Icons.vertical_split_outlined),
                ),
                  ]),
                ),
              ),
              if (hasDocument && !compact)
                Flexible(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Tooltip(
                        message: controller.filePath ?? controller.fileName,
                        child: Text(
                          controller.fileName,
                          maxLines: 1,
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                )
              else
                const Spacer(),
              SizedBox(
                width: searchWidth,
                child: TextField(
                  controller: search,
                  focusNode: searchFocus,
                  enabled: hasDocument,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: InputDecoration(
                    hintText: 'Buscar (⌘F)',
                    hintStyle: const TextStyle(fontSize: 12),
                    prefixIcon: const Icon(Icons.search, size: 16),
                    prefixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    suffixIcon: controller.quickSearch.isEmpty
                        ? null
                        : IconButton(
                            iconSize: 14,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                            icon: const Icon(Icons.close),
                            onPressed: () => controller.setQuickSearch(''),
                          ),
                  ),
                  onChanged: controller.setQuickSearch,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.compact = false,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool compact;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        iconSize: 18,
        tooltip: tooltip ?? label,
        onPressed: onPressed,
        icon: Icon(icon),
      );
    }
    final button = TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12.5)),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class _WelcomeView extends StatelessWidget {
  const _WelcomeView({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.table_chart_outlined, size: 56, color: onSurface.withValues(alpha: 0.25)),
          const SizedBox(height: 16),
          const Text(
            'CSViewer',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Abra um arquivo CSV para visualizar, ordenar e filtrar os registros.',
            style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.folder_open, size: 18),
            label: const Text('Abrir arquivo…'),
          ),
          const SizedBox(height: 10),
          Text(
            'ou arraste um arquivo para esta janela',
            style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.45)),
          ),
        ],
      ),
    );
  }
}

/// Delimiter / encoding / header overrides for files the detector gets wrong.
class _ReadOptionsDialog extends StatefulWidget {
  const _ReadOptionsDialog({required this.controller});

  final AppController controller;

  @override
  State<_ReadOptionsDialog> createState() => _ReadOptionsDialogState();
}

class _ReadOptionsDialogState extends State<_ReadOptionsDialog> {
  late String _delimiter;
  late String _encoding;
  late bool _hasHeader;
  late ReadMode _mode;

  @override
  void initState() {
    super.initState();
    final options = widget.controller.options;
    _delimiter = options.delimiter ?? widget.controller.delimiter;
    _encoding = options.encoding;
    _hasHeader = options.hasHeaderRow;
    _mode = options.mode;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Opções de leitura'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _delimiter,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Delimitador'),
              items: [
                for (final d in supportedDelimiters)
                  DropdownMenuItem(value: d, child: Text(delimiterLabel(d))),
              ],
              onChanged: (value) => setState(() => _delimiter = value ?? ','),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _encoding,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Codificação'),
              items: [
                for (final e in supportedEncodings)
                  DropdownMenuItem(value: e, child: Text(e)),
              ],
              onChanged: (value) => setState(() => _encoding = value ?? encodingAuto),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              value: _hasHeader,
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text('A primeira linha contém os nomes das colunas'),
              onChanged: (value) => setState(() => _hasHeader = value),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<ReadMode>(
              initialValue: _mode,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Leitura',
                helperText: 'Arquivos grandes são lidos do disco sob demanda.',
              ),
              items: const [
                DropdownMenuItem(value: ReadMode.auto, child: Text('Automático')),
                DropdownMenuItem(value: ReadMode.memory, child: Text('Carregar na memória')),
                DropdownMenuItem(value: ReadMode.streaming, child: Text('Streaming do disco')),
              ],
              onChanged: (value) => setState(() => _mode = value ?? ReadMode.auto),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            LoadOptions(
              delimiter: _delimiter,
              encoding: _encoding,
              hasHeaderRow: _hasHeader,
              mode: _mode,
            ),
          ),
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}
