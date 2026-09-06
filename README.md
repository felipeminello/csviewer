# CSViewer para macOS

Visualizador de CSV para macOS, inspirado no [CSViewer](https://csviewer.com/) do Windows:
abrir um arquivo, ver os registros em grade, **ordenar por coluna** (crescente/decrescente) e
**filtrar por valores de coluna**, encadeando quantos filtros forem necessários.

Feito em Flutter (o projeto também compila para Windows e Linux).

## Rodando

```bash
flutter pub get
flutter run -d macos          # desenvolvimento
flutter build macos --release # gera build/macos/Build/Products/Release/CSViewer.app
```

Para instalar: arraste `CSViewer.app` para a pasta *Aplicativos*. O app não é assinado com
uma conta de desenvolvedor Apple, então na primeira execução pode ser preciso abrir com
botão direito → *Abrir*.

## O que dá para fazer

**Abrir**
- Botão *Abrir* (⌘O), arrastando o arquivo para a janela, ou pelo Finder (duplo clique /
  *Abrir com* / soltar no ícone do Dock).
- Delimitador (`,` `;` tab `|`) e codificação (UTF-8 com/sem BOM, UTF-16, Latin-1) são
  detectados automaticamente; o botão *Leitura* permite forçar outra opção e dizer se a
  primeira linha é cabeçalho.
- O parser segue o RFC 4180: aspas, vírgulas e quebras de linha dentro de campos, `""`
  escapado, CRLF/CR/LF. A leitura acontece fora da thread de UI.

**Ordenar**
- Clique no cabeçalho: crescente → decrescente → sem ordenação.
- **Shift + clique** adiciona a coluna como critério secundário (a ordem dos cliques aparece
  como um número ao lado da seta).
- A ordenação respeita o tipo detectado da coluna: número é comparado como número
  (inclusive `1.234,56`, `R$`, `%` e negativos entre parênteses), data como data
  (`2024-01-31` e `31/01/2024`), o resto como texto. Campos vazios vão para o fim.

**Filtrar**
- *Filtro* (⌘L) ou botão direito no cabeçalho da coluna → *Filtrar por valores…*.
- Condições: contém / não contém, igual / diferente, começa com, termina com, está vazio,
  não está vazio, maior, maior ou igual, menor, menor ou igual, entre, é um de (lista de
  valores distintos com busca) e regex. Com ou sem diferenciar maiúsculas.
- **Filtros são encadeados**: cada novo filtro entra na barra como um chip, ligado ao
  anterior por **E** ou **OU** (clique no conector para trocar). `E` tem precedência sobre
  `OU`, como em SQL: `A E B OU C` é lido como `(A E B) OU C`.
- Cada filtro pode ser desativado temporariamente (sem perder a configuração), editado
  (clique no chip) ou removido.
- A busca rápida (⌘F) filtra por texto em todas as colunas ao mesmo tempo e destaca os
  trechos encontrados.

**Ver e exportar**
- Painel do registro (⌘I) com todos os campos da linha selecionada e botão de copiar.
- Mostrar/ocultar colunas (⇧⌘C), redimensionar arrastando a borda do cabeçalho, duplo
  clique na borda ajusta a largura ao conteúdo.
- *Exportar* (⌘E) grava um CSV com exatamente o que está na tela: filtros aplicados, ordem
  atual e apenas as colunas visíveis.
- Barra de status: registros exibidos / total, colunas, ordenação ativa, delimitador,
  codificação e tamanho do arquivo.

## Atalhos

| Ação | Atalho |
| --- | --- |
| Abrir | ⌘O |
| Recarregar | ⌘R |
| Exportar visão atual | ⌘E |
| Fechar arquivo | ⌘W |
| Buscar | ⌘F |
| Copiar registro | ⌘C |
| Adicionar filtro | ⌘L |
| Limpar filtros | ⇧⌘K |
| Painel do registro | ⌘I |
| Colunas | ⇧⌘C |
| Navegar entre registros | ↑ ↓ · Page Up/Down · Home/End |

## Estrutura

```
lib/
  main.dart                      menus nativos do macOS e atalhos
  src/model/                     tabela, tipos de coluna, regras de filtro
  src/services/                  parser RFC 4180, detecção de delimitador/codificação,
                                 leitura em isolate, exportação
  src/state/app_controller.dart  filtros, ordenação, colunas e a visão resultante
  src/ui/                        grade virtualizada, barra de filtros, diálogos, painel
macos/Runner/AppDelegate.swift   ponte para arquivos abertos pelo Finder
```

A grade é virtualizada (só as linhas visíveis são construídas) e as chaves de ordenação são
calculadas uma vez por coluna e reaproveitadas, então reordenar arquivos grandes é imediato.
O arquivo é mantido inteiro em memória — o alvo são os CSVs do dia a dia (dezenas a centenas
de milhares de linhas), não arquivos de vários GB.

## Testes

```bash
flutter test
```

- `test/csv_parser_test.dart` — parser, detecção de delimitador, codificação, tipos.
- `test/app_controller_test.dart` — ordenação, cadeia de filtros com E/OU, exportação.
- `test/ui_smoke_test.dart` — a interface de ponta a ponta; também grava capturas em
  `build/screenshots/`.
