import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Espaço entre dois campos. Precisa passar do rótulo flutuante, que sobe para
/// cima da borda do campo de baixo — com menos que isso os dois se encostam.
const double kFieldGap = 18;

/// Espaço entre blocos de assunto diferente dentro do mesmo diálogo.
const double kBlockGap = 22;

/// Caixa comum às janelas de filtro, colunas e leitura: mesmas margens, mesmo
/// bloco de título e a mesma linha de ações, para as três parecerem o mesmo
/// aplicativo.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.child,
    required this.actions,
    this.subtitle,
    this.width = 460,
    this.scrollable = true,
  });

  final String title;

  /// Uma linha explicando o que a janela faz. Some quando não há nada útil.
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final double width;

  /// Conteúdo de altura livre rola; quem já tem lista própria com altura fixa
  /// (as colunas) passa `false`.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(width, math.max(280.0, screen.width - 80));

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title),
          if (subtitle != null) ...[
            const SizedBox(height: 5),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: math.max(200.0, screen.height - 180)),
        child: SizedBox(
          width: dialogWidth,
          // O recuo vai dentro da área rolável: o rótulo flutuante do primeiro
          // campo sobe para fora do campo e a rolagem cortaria o topo dele.
          child: scrollable
              ? SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 6),
                  child: child,
                )
              : child,
        ),
      ),
      actions: actions,
    );
  }
}

/// Select com o mesmo desenho dos campos de texto: rótulo flutuante, borda
/// arredondada e um menu que não passa da altura da tela.
class AppSelect<T> extends StatelessWidget {
  const AppSelect({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.helperText,
  });

  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? helperText;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      borderRadius: BorderRadius.circular(8),
      menuMaxHeight: 340,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
      decoration: InputDecoration(labelText: label, helperText: helperText),
      items: items,
      onChanged: onChanged,
    );
  }
}

/// Campo de busca das listas dos diálogos.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
    this.controller,
  });

  final String hintText;
  final ValueChanged<String> onChanged;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search, size: 17),
        prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 20),
      ),
    );
  }
}

/// Moldura das listas roláveis: a mesma borda, o mesmo raio e o mesmo fundo
/// dos campos, para a lista fazer parte do formulário.
class ListPanel extends StatelessWidget {
  const ListPanel({super.key, required this.child, this.height});

  final Widget child;
  final double? height;

  @override
  Widget build(BuildContext context) {
    // Material, e não um Container decorado: as linhas da lista pintam o
    // realce do toque no Material mais próximo, e uma caixa colorida no meio
    // esconderia esse realce.
    return Material(
      color: fieldFill(context),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        side: fieldBorderSide(context),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SizedBox(height: height, child: child),
    );
  }
}

/// Título curto de um bloco do formulário ("Valores", "Colunas do arquivo").
class BlockLabel extends StatelessWidget {
  const BlockLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontSize: 12.5,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
          ),
    );
  }
}

/// Borda dos campos, lida do tema para as molduras acompanharem os inputs.
BorderSide fieldBorderSide(BuildContext context) {
  final border = Theme.of(context).inputDecorationTheme.enabledBorder;
  if (border is OutlineInputBorder) return border.borderSide;
  return BorderSide(color: Theme.of(context).dividerColor);
}

/// Fundo dos campos, pela mesma razão.
Color fieldFill(BuildContext context) =>
    Theme.of(context).inputDecorationTheme.fillColor ??
    Theme.of(context).colorScheme.surfaceContainerLowest;
