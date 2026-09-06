import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/services/open_file_channel.dart';
import 'src/state/app_controller.dart';
import 'src/ui/home_page.dart';
import 'src/ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CsViewerApp());
}

class CsViewerApp extends StatefulWidget {
  const CsViewerApp({super.key});

  @override
  State<CsViewerApp> createState() => _CsViewerAppState();
}

class _CsViewerAppState extends State<CsViewerApp> {
  final AppController _controller = AppController();
  final GlobalKey<HomePageState> _homeKey = GlobalKey<HomePageState>();

  @override
  void initState() {
    super.initState();
    OpenFileChannel.listen(_controller.openPath);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final pending = await OpenFileChannel.consumePending();
      if (pending.isNotEmpty) _controller.openPath(pending.first);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  HomePageState? get _home => _homeKey.currentState;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CSViewer',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: AnimatedBuilder(
        // Rebuilt so the menu items enable and disable with the document.
        animation: _controller,
        child: HomePage(key: _homeKey, controller: _controller),
        builder: (context, child) => _MenuHost(
          controller: _controller,
          openFile: () => _home?.openFile(),
          reloadFile: () => _home?.reloadFile(),
          exportView: () => _home?.exportView(),
          closeFile: _controller.closeDocument,
          copyRow: () => _home?.copySelectedRow(),
          focusSearch: () => _home?.focusSearch(),
          clearFilters: _controller.clearFilters,
          addFilter: () => _home?.addFilter(),
          toggleInspector: _controller.toggleInspector,
          showColumns: () => _home?.showColumnsDialog(),
          clearSort: _controller.clearSort,
          child: child!,
        ),
      ),
    );
  }
}

/// Wires the commands to the macOS menu bar, and to plain keyboard shortcuts
/// on the other desktop platforms.
class _MenuHost extends StatelessWidget {
  const _MenuHost({
    required this.controller,
    required this.child,
    required this.openFile,
    required this.reloadFile,
    required this.exportView,
    required this.closeFile,
    required this.copyRow,
    required this.focusSearch,
    required this.clearFilters,
    required this.addFilter,
    required this.toggleInspector,
    required this.showColumns,
    required this.clearSort,
  });

  final AppController controller;
  final Widget child;
  final VoidCallback openFile;
  final VoidCallback reloadFile;
  final VoidCallback exportView;
  final VoidCallback closeFile;
  final VoidCallback copyRow;
  final VoidCallback focusSearch;
  final VoidCallback clearFilters;
  final VoidCallback addFilter;
  final VoidCallback toggleInspector;
  final VoidCallback showColumns;
  final VoidCallback clearSort;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) {
      return CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          const SingleActivator(LogicalKeyboardKey.keyO, control: true): openFile,
          const SingleActivator(LogicalKeyboardKey.keyR, control: true): reloadFile,
          const SingleActivator(LogicalKeyboardKey.keyE, control: true): exportView,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): focusSearch,
          const SingleActivator(LogicalKeyboardKey.keyC, control: true): copyRow,
          const SingleActivator(LogicalKeyboardKey.keyL, control: true): addFilter,
          const SingleActivator(LogicalKeyboardKey.keyI, control: true): toggleInspector,
          const SingleActivator(LogicalKeyboardKey.keyK, control: true, shift: true): clearFilters,
        },
        child: Focus(autofocus: true, child: child),
      );
    }
    return PlatformMenuBar(
      menus: <PlatformMenuItem>[
        PlatformMenu(
          label: 'CSViewer',
          menus: <PlatformMenuItem>[
            const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
                const PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hideOtherApplications,
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: 'Arquivo',
          menus: <PlatformMenuItem>[
            PlatformMenuItem(
              label: 'Abrir…',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyO, meta: true),
              onSelected: openFile,
            ),
            PlatformMenuItem(
              label: 'Recarregar',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyR, meta: true),
              onSelected: controller.hasDocument ? reloadFile : null,
            ),
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: 'Exportar visão atual…',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyE, meta: true),
                  onSelected: controller.hasDocument ? exportView : null,
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                PlatformMenuItem(
                  label: 'Fechar arquivo',
                  shortcut: const SingleActivator(LogicalKeyboardKey.keyW, meta: true),
                  onSelected: controller.hasDocument ? closeFile : null,
                ),
              ],
            ),
          ],
        ),
        PlatformMenu(
          label: 'Editar',
          menus: <PlatformMenuItem>[
            PlatformMenuItem(
              label: 'Copiar registro',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyC, meta: true),
              onSelected: controller.hasDocument ? copyRow : null,
            ),
            PlatformMenuItem(
              label: 'Buscar',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyF, meta: true),
              onSelected: controller.hasDocument ? focusSearch : null,
            ),
          ],
        ),
        PlatformMenu(
          label: 'Filtros',
          menus: <PlatformMenuItem>[
            PlatformMenuItem(
              label: 'Adicionar filtro…',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyL, meta: true),
              onSelected: controller.hasDocument ? addFilter : null,
            ),
            PlatformMenuItem(
              label: 'Limpar filtros',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyK, meta: true, shift: true),
              onSelected: controller.hasDocument ? clearFilters : null,
            ),
            PlatformMenuItem(
              label: 'Limpar ordenação',
              onSelected: controller.hasDocument ? clearSort : null,
            ),
          ],
        ),
        PlatformMenu(
          label: 'Visualizar',
          menus: <PlatformMenuItem>[
            PlatformMenuItem(
              label: 'Painel do registro',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyI, meta: true),
              onSelected: controller.hasDocument ? toggleInspector : null,
            ),
            PlatformMenuItem(
              label: 'Colunas…',
              shortcut: const SingleActivator(LogicalKeyboardKey.keyC, meta: true, shift: true),
              onSelected: controller.hasDocument ? showColumns : null,
            ),
            PlatformMenuItemGroup(
              members: <PlatformMenuItem>[
                const PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.toggleFullScreen,
                ),
                const PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.minimizeWindow,
                ),
                const PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.zoomWindow),
              ],
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}
