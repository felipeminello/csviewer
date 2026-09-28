class SortSpec {
  const SortSpec(this.column, {this.ascending = true});
  final int column;
  final bool ascending;

  @override
  bool operator ==(Object other) =>
      other is SortSpec && other.column == column && other.ascending == ascending;

  @override
  int get hashCode => Object.hash(column, ascending);

  @override
  String toString() => 'SortSpec($column, ${ascending ? 'asc' : 'desc'})';
}
