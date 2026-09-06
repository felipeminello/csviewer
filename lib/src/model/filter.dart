import 'column_meta.dart';

enum FilterOp {
  contains,
  notContains,
  equals,
  notEquals,
  startsWith,
  endsWith,
  isEmpty,
  isNotEmpty,
  greater,
  greaterOrEqual,
  less,
  lessOrEqual,
  between,
  inSet,
  matchesRegex,
}

extension FilterOpLabel on FilterOp {
  String get label {
    switch (this) {
      case FilterOp.contains:
        return 'contém';
      case FilterOp.notContains:
        return 'não contém';
      case FilterOp.equals:
        return 'igual a';
      case FilterOp.notEquals:
        return 'diferente de';
      case FilterOp.startsWith:
        return 'começa com';
      case FilterOp.endsWith:
        return 'termina com';
      case FilterOp.isEmpty:
        return 'está vazio';
      case FilterOp.isNotEmpty:
        return 'não está vazio';
      case FilterOp.greater:
        return 'maior que';
      case FilterOp.greaterOrEqual:
        return 'maior ou igual a';
      case FilterOp.less:
        return 'menor que';
      case FilterOp.lessOrEqual:
        return 'menor ou igual a';
      case FilterOp.between:
        return 'entre';
      case FilterOp.inSet:
        return 'é um de';
      case FilterOp.matchesRegex:
        return 'regex';
    }
  }

  bool get needsValue => this != FilterOp.isEmpty && this != FilterOp.isNotEmpty && this != FilterOp.inSet;
  bool get needsSecondValue => this == FilterOp.between;
  bool get isComparison =>
      this == FilterOp.greater ||
      this == FilterOp.greaterOrEqual ||
      this == FilterOp.less ||
      this == FilterOp.lessOrEqual ||
      this == FilterOp.between;
}

/// How a rule attaches to the ones before it. `and` binds tighter than `or`,
/// the same way it does in SQL, so `A and B or C` reads as `(A and B) or C`.
enum FilterJoin { and, or }

class FilterRule {
  FilterRule({
    required this.column,
    required this.op,
    this.value = '',
    this.value2 = '',
    Set<String>? values,
    this.caseSensitive = false,
    this.join = FilterJoin.and,
    this.enabled = true,
  }) : values = values ?? <String>{};

  final int column;
  final FilterOp op;
  final String value;
  final String value2;
  final Set<String> values;
  final bool caseSensitive;
  final FilterJoin join;
  final bool enabled;

  FilterRule copyWith({
    int? column,
    FilterOp? op,
    String? value,
    String? value2,
    Set<String>? values,
    bool? caseSensitive,
    FilterJoin? join,
    bool? enabled,
  }) {
    return FilterRule(
      column: column ?? this.column,
      op: op ?? this.op,
      value: value ?? this.value,
      value2: value2 ?? this.value2,
      values: values ?? this.values,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      join: join ?? this.join,
      enabled: enabled ?? this.enabled,
    );
  }

  String describe(List<ColumnMeta> columns) {
    final name = column < columns.length ? columns[column].name : 'coluna $column';
    switch (op) {
      case FilterOp.isEmpty:
      case FilterOp.isNotEmpty:
        return '$name ${op.label}';
      case FilterOp.between:
        return '$name ${op.label} $value e $value2';
      case FilterOp.inSet:
        if (values.length <= 3) {
          return '$name ${op.label} ${values.map(_display).join(', ')}';
        }
        return '$name ${op.label} ${values.length} valores';
      default:
        return '$name ${op.label} "$value"';
    }
  }

  static String _display(String raw) => raw.isEmpty ? '(vazio)' : raw;
}

/// A rule prepared for fast repeated evaluation (regex compiled, comparison
/// operands parsed once instead of once per row).
class _CompiledRule {
  _CompiledRule(this.rule, ColumnMeta meta) : _meta = meta {
    _needle = rule.caseSensitive ? rule.value : rule.value.toLowerCase();
    if (rule.op == FilterOp.matchesRegex) {
      try {
        _regex = RegExp(rule.value, caseSensitive: rule.caseSensitive);
      } on FormatException {
        _regex = null;
      }
    }
    if (rule.op.isComparison) {
      _bound1 = _operand(rule.value);
      _bound2 = _operand(rule.value2);
    }
    if (rule.op == FilterOp.inSet) {
      _set = rule.caseSensitive ? rule.values : rule.values.map((v) => v.toLowerCase()).toSet();
    }
  }

  final FilterRule rule;
  final ColumnMeta _meta;
  late final String _needle;
  RegExp? _regex;
  Comparable<Object>? _bound1;
  Comparable<Object>? _bound2;
  Set<String>? _set;

  Comparable<Object>? _operand(String raw) {
    if (raw.trim().isEmpty) return null;
    switch (_meta.type) {
      case ColumnType.number:
        return _meta.number(raw);
      case ColumnType.date:
        return _meta.date(raw);
      case ColumnType.text:
        return raw.toLowerCase();
    }
  }

  Comparable<Object>? _cellOperand(String raw) {
    if (raw.trim().isEmpty) return null;
    switch (_meta.type) {
      case ColumnType.number:
        return _meta.number(raw);
      case ColumnType.date:
        return _meta.date(raw);
      case ColumnType.text:
        return raw.toLowerCase();
    }
  }

  bool matches(List<String> row) {
    final raw = rule.column < row.length ? row[rule.column] : '';
    switch (rule.op) {
      case FilterOp.isEmpty:
        return raw.trim().isEmpty;
      case FilterOp.isNotEmpty:
        return raw.trim().isNotEmpty;
      case FilterOp.matchesRegex:
        return _regex?.hasMatch(raw) ?? false;
      case FilterOp.inSet:
        final probe = rule.caseSensitive ? raw : raw.toLowerCase();
        return _set!.contains(probe);
      case FilterOp.greater:
      case FilterOp.greaterOrEqual:
      case FilterOp.less:
      case FilterOp.lessOrEqual:
      case FilterOp.between:
        return _compare(raw);
      default:
        break;
    }
    final hay = rule.caseSensitive ? raw : raw.toLowerCase();
    switch (rule.op) {
      case FilterOp.contains:
        return hay.contains(_needle);
      case FilterOp.notContains:
        return !hay.contains(_needle);
      case FilterOp.equals:
        return hay == _needle;
      case FilterOp.notEquals:
        return hay != _needle;
      case FilterOp.startsWith:
        return hay.startsWith(_needle);
      case FilterOp.endsWith:
        return hay.endsWith(_needle);
      default:
        return true;
    }
  }

  bool _compare(String raw) {
    final cell = _cellOperand(raw);
    if (cell == null) return false;
    if (_bound1 == null) return false;
    final c1 = Comparable.compare(cell, _bound1!);
    switch (rule.op) {
      case FilterOp.greater:
        return c1 > 0;
      case FilterOp.greaterOrEqual:
        return c1 >= 0;
      case FilterOp.less:
        return c1 < 0;
      case FilterOp.lessOrEqual:
        return c1 <= 0;
      case FilterOp.between:
        if (_bound2 == null) return false;
        return c1 >= 0 && Comparable.compare(cell, _bound2!) <= 0;
      default:
        return true;
    }
  }
}

/// Evaluates a chain of rules against rows. Consecutive `and` rules form a
/// group; groups are combined with `or`.
class FilterProgram {
  FilterProgram._(this._groups);

  final List<List<_CompiledRule>> _groups;

  bool get isEmpty => _groups.isEmpty;

  factory FilterProgram.compile(List<FilterRule> rules, List<ColumnMeta> columns) {
    final groups = <List<_CompiledRule>>[];
    for (final rule in rules) {
      if (!rule.enabled) continue;
      if (rule.column >= columns.length) continue;
      final compiled = _CompiledRule(rule, columns[rule.column]);
      if (groups.isEmpty || rule.join == FilterJoin.or) {
        groups.add(<_CompiledRule>[compiled]);
      } else {
        groups.last.add(compiled);
      }
    }
    return FilterProgram._(groups);
  }

  bool matches(List<String> row) {
    if (_groups.isEmpty) return true;
    for (final group in _groups) {
      var all = true;
      for (final rule in group) {
        if (!rule.matches(row)) {
          all = false;
          break;
        }
      }
      if (all) return true;
    }
    return false;
  }
}
