# CSViewer para macOS

Visualizador de CSV para macOS, inspirado no [CSViewer](https://csviewer.com/) do Windows:
abrir um arquivo, ver os registros em grade, **ordenar por coluna** (crescente/decrescente) e
**filtrar por valores de coluna**, encadeando quantos filtros forem necessários.

Arquivos de **vários gigabytes** são abertos sem serem carregados na memória — veja
[Arquivos grandes](#arquivos-grandes).

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

**Arquivos grandes**
- Acima de 128 MB o arquivo passa a ser lido do disco sob demanda; abaixo disso fica na
  memória (tudo instantâneo). O botão *Leitura* permite forçar um dos dois modos, e a barra
  de status mostra qual está em uso.
- A abertura é imediata: os cabeçalhos aparecem na hora e os registros vão surgindo conforme
  o índice é construído, com a barra de progresso mostrando o andamento.

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

## Arquivos grandes

Nada de carregar o arquivo inteiro. Ao abrir um CSV acima de 128 MB o app usa um leitor
indexado, que roda em um isolate separado (a interface nunca trava):

1. **Índice.** Uma passada sequencial pelos bytes encontra o começo de cada registro —
   respeitando aspas, campos com quebra de linha e CRLF — e guarda **um offset a cada 256
   registros**. São ~2 MB de índice para 25 milhões de linhas, e os registros já indexados
   aparecem na tela enquanto o resto é lido.
2. **Leitura por janelas.** A grade pede só as linhas visíveis; o leitor traduz a posição em
   bloco, lê ~25 KB do disco e decodifica apenas aqueles registros. Ir para o fim de um
   arquivo de 25 milhões de linhas é instantâneo.
3. **Filtros e busca.** Fazem uma varredura sequencial do arquivo com progresso e
   cancelamento (um filtro novo aborta a varredura anterior). Os registros são percorridos
   direto nos bytes e **só os campos que o filtro consulta viram texto** — isso deixou a
   varredura ~3x mais rápida do que decodificar tudo. O resultado é uma lista de índices
   (4 bytes por registro aprovado); sem filtro nenhum, nem essa lista existe.
4. **Exportação.** Escrita direto no disco: quando a visão está na ordem do arquivo, é uma
   única passada sequencial; quando está ordenada, vai página por página, lendo cada página
   na ordem do arquivo.

Medições em um CSV de **2,24 GB com 25 milhões de registros** (`tool/benchmark_grande.dart`,
MacBook com SSD):

| Operação | Tempo | Memória do processo |
| --- | --- | --- |
| Abrir (cabeçalhos e tipos na tela) | 73 ms | — |
| Indexar os 25 milhões de registros | ~11 s | 180 MB |
| Ler um registro qualquer (início/meio/fim) | 0–1 ms | 182 MB |
| Filtrar por uma coluna (3,1 milhões de resultados) | 5,0 s | 212 MB |
| Três filtros + ordenação (78 mil resultados) | 5,4 s | 269 MB |
| Exportar os 78 mil registros ordenados | 3,0 s | 305 MB |

Na interface, abrir esse mesmo arquivo custou ~200 MB de pico durante a indexação e 174 MB
parado.

**Limites conscientes**

- **Ordenação**: ordenar exige uma chave por registro na memória, então é permitida em até
  2 milhões de registros na visão. Acima disso o app avisa e desfaz a ordenação, pedindo que
  se filtre antes — em vez de estourar a memória.
- **UTF-16**: o leitor indexado trabalha sobre bytes e cobre UTF-8, Latin-1 e ASCII. Um
  arquivo UTF-16 cai no modo memória (são raros em tamanhos grandes).
- Alterar delimitador, codificação ou modo de leitura reindexa o arquivo.

## Estrutura

```
lib/
  main.dart                        menus nativos do macOS e atalhos
  src/model/                       tabela, tipos de coluna, regras de filtro, ordenação
  src/services/csv_parser.dart     parser RFC 4180 e detecção de delimitador/codificação
  src/services/csv_index.dart      varredura de bytes que acha o início de cada registro
  src/services/csv_byte_records.dart  registros preguiçosos: campo só vira texto se for lido
  src/services/csv_worker.dart     isolate que indexa, lê janelas, filtra, ordena e exporta
  src/services/csv_loader.dart     leitura em memória (arquivos comuns)
  src/data/csv_source.dart         a fonte de dados da grade: memória ou streaming
  src/state/app_controller.dart    filtros, ordenação, colunas e a visão resultante
  src/ui/                          grade virtualizada, barra de filtros, diálogos, painel
macos/Runner/AppDelegate.swift     ponte para arquivos abertos pelo Finder
tool/benchmark_grande.dart         medição do modo streaming em arquivos de vários GB
```

A grade é virtualizada (só as linhas visíveis são construídas). No modo memória as chaves de
ordenação são calculadas uma vez por coluna e reaproveitadas, então reordenar é imediato.

## Testes

```bash
flutter test
```

- `test/csv_parser_test.dart` — parser, detecção de delimitador, codificação, tipos.
- `test/csv_index_test.dart` — o indexador de bytes casa com o parser em qualquer tamanho de
  bloco lido, com aspas, quebras de linha dentro de campos, CRLF e linhas em branco.
- `test/csv_byte_records_test.dart` — os registros preguiçosos entregam exatamente o mesmo
  que o parser (inclusive em 200 arquivos aleatórios).
- `test/app_controller_test.dart` — ordenação, cadeia de filtros com E/OU e exportação,
  rodados **duas vezes**: com o arquivo em memória e com o leitor de streaming.
- `test/streaming_source_test.dart` — paridade entre os dois leitores em um arquivo de
  múltiplos blocos e o comportamento do limite de ordenação.
- `test/ui_smoke_test.dart` — a interface de ponta a ponta; também grava capturas em
  `build/screenshots/`.

Para medir em um arquivo de verdade:

```bash
python3 tool/gerar_grande.py build/gigante.csv 250   # ~2,3 GB, 25 milhões de linhas
flutter test tool/benchmark_grande.dart
```
