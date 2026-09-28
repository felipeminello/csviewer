import 'dart:math' as math;

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
import 'dialogs.dart';
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

  /// Volta à tela inicial, como se o app tivesse acabado de abrir: o arquivo
  /// sai da memória junto com filtros, ordenação, busca e seleção.
  void closeFile() {
    if (!controller.hasDocument) return;
    _searchFocus.unfocus();
    ScaffoldMessenger.of(context).clearSnackBars();
    controller.closeDocument();
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
                      onClose: closeFile,
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

/// Um botão da barra de ferramentas: o mesmo dado alimenta o widget e a
/// estimativa de largura que decide quando os rótulos ainda cabem.
class _ToolSpec {
  const _ToolSpec(this.icon, this.label, this.onPressed, {this.tooltip});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;
}

// Medidas da barra: o miolo de um botão com rótulo (padding + ícone + espaço),
// a largura de um IconButton e as margens do nome do arquivo.
const double _toolLabelSize = 12.5;
const double _toolButtonChrome = 46;
const double _toolIconButtonWidth = 40;
const double _fileNameMargin = 24;
const double _fileNameMinWidth = 80;
const double _fileNameMaxWidth = 260;

/// Limite superior da largura do bloco de botões com rótulo. É medido a partir
/// dos rótulos reais (e da escala de texto do sistema) em vez de fixado em uma
/// constante: era um número chutado que deixava "Exportar" fora da janela.
double _labelledClusterWidth(
  BuildContext context,
  List<_ToolSpec> specs, {
  required bool withInspector,
}) {
  final style = Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: _toolLabelSize) ??
      const TextStyle(fontSize: _toolLabelSize);
  final scaler = MediaQuery.textScalerOf(context);
  var width = withInspector ? _toolIconButtonWidth : 0.0;
  for (final spec in specs) {
    final painter = TextPainter(
      text: TextSpan(text: spec.label, style: style),
      textDirection: Directionality.of(context),
      textScaler: scaler,
    )..layout();
    width += painter.width + _toolButtonChrome;
  }
  return width;
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.search,
    required this.searchFocus,
    required this.onOpen,
    required this.onReload,
    required this.onExport,
    required this.onClose,
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
  final VoidCallback onClose;
  final VoidCallback onAddFilter;
  final VoidCallback onColumns;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final hasDocument = controller.hasDocument;
    final colors = GridColors.of(context);
    final buttons = <_ToolSpec>[
      _ToolSpec(Icons.folder_open, 'Abrir', onOpen),
      _ToolSpec(Icons.refresh, 'Recarregar', hasDocument ? onReload : null),
      _ToolSpec(
        Icons.filter_alt,
        'Filtro',
        hasDocument ? onAddFilter : null,
        tooltip: 'Adicionar filtro (⌘L)',
      ),
      _ToolSpec(Icons.view_column, 'Colunas', hasDocument ? onColumns : null),
      _ToolSpec(
        Icons.tune,
        'Leitura',
        hasDocument ? onOptions : null,
        tooltip: 'Delimitador, codificação e cabeçalho',
      ),
      _ToolSpec(
        Icons.ios_share,
        'Exportar',
        hasDocument ? onExport : null,
        tooltip: 'Salvar a visão atual (filtrada e ordenada) como CSV',
      ),
    ];

    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.header,
        border: Border(bottom: BorderSide(color: colors.gridLine)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final searchWidth = constraints.maxWidth < 620 ? 150.0 : 240.0;
          // Os botões têm prioridade sobre o nome do arquivo: ele fica só com a
          // sobra, e os rótulos viram ícones antes de qualquer corte.
          final free = constraints.maxWidth -
              searchWidth -
              (hasDocument ? _toolIconButtonWidth : 0); // botão de fechar
          final labelled =
              _labelledClusterWidth(context, buttons, withInspector: hasDocument);
          final compact = free < labelled;
          final nameWidth = hasDocument && !compact
              ? math.min(_fileNameMaxWidth, free - labelled - _fileNameMargin)
              : 0.0;

          return Row(
            children: [
              // Fica com tudo que o nome do arquivo e a busca não usam; só rola
              // em janelas estreitas demais até para os ícones.
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final spec in buttons)
                        _ToolButton(
                          icon: spec.icon,
                          label: spec.label,
                          tooltip: spec.tooltip,
                          compact: compact,
                          onPressed: spec.onPressed,
                        ),
                      if (hasDocument)
                        IconButton(
                          iconSize: 18,
                          tooltip: 'Painel do registro (⌘I)',
                          isSelected: controller.showInspector,
                          onPressed: controller.toggleInspector,
                          icon: const Icon(Icons.vertical_split_outlined),
                        ),
                    ],
                  ),
                ),
              ),
              if (nameWidth >= _fileNameMinWidth)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _fileNameMargin / 2),
                  child: SizedBox(
                    width: nameWidth,
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
              // Fora do bloco que vira ícones: fechar fica sempre à vista, colado
              // ao nome do arquivo como o "x" de uma aba.
              if (hasDocument)
                IconButton(
                  iconSize: 18,
                  tooltip: 'Fechar arquivo (⌘W)',
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
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
                    // Mais apertado que os campos dos diálogos: aqui a altura é
                    // a dos 46px da barra, não a de um formulário.
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
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
    return AppDialog(
      title: 'Opções de leitura',
      subtitle: 'Para quando a detecção automática errar o formato do arquivo.',
      width: 420,
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSelect<String>(
            label: 'Delimitador',
            value: _delimiter,
            items: [
              for (final d in supportedDelimiters)
                DropdownMenuItem(value: d, child: Text(delimiterLabel(d))),
            ],
            onChanged: (value) => setState(() => _delimiter = value ?? ','),
          ),
          const SizedBox(height: kFieldGap),
          AppSelect<String>(
            label: 'Codificação',
            value: _encoding,
            items: [
              for (final e in supportedEncodings) DropdownMenuItem(value: e, child: Text(e)),
            ],
            onChanged: (value) => setState(() => _encoding = value ?? encodingAuto),
          ),
          const SizedBox(height: kFieldGap),
          AppSelect<ReadMode>(
            label: 'Leitura',
            value: _mode,
            helperText: 'Arquivos grandes são lidos do disco sob demanda.',
            items: const [
              DropdownMenuItem(value: ReadMode.auto, child: Text('Automático')),
              DropdownMenuItem(value: ReadMode.memory, child: Text('Carregar na memória')),
              DropdownMenuItem(value: ReadMode.streaming, child: Text('Streaming do disco')),
            ],
            onChanged: (value) => setState(() => _mode = value ?? ReadMode.auto),
          ),
          const SizedBox(height: kBlockGap),
          // O interruptor ganha a mesma moldura dos campos para não ficar
          // solto entre os selects.
          ListPanel(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: SwitchListTile(
                value: _hasHeader,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'A primeira linha contém os nomes das colunas',
                  style: TextStyle(fontSize: 13),
                ),
                onChanged: (value) => setState(() => _hasHeader = value),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
