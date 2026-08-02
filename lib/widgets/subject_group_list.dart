import 'package:flutter/material.dart';

/// Lista de tarjetas plegables agrupadas por materia, con encabezado
/// "Materia · N <algo>" (ej. "Hebreo · 5 archivos"). Se usa en "Mis tareas"
/// (archivos), "Mis reuniones" y "Material docente" para que listas largas
/// no se vuelvan una sola columna interminable de tarjetas.
class SubjectGroupList<T> extends StatelessWidget {
  final List<T> items;
  final String Function(T item) subjectOf;
  final Widget Function(T item) itemBuilder;
  final String Function(int count) countLabelOf;
  final EdgeInsetsGeometry padding;

  const SubjectGroupList({
    super.key,
    required this.items,
    required this.subjectOf,
    required this.itemBuilder,
    required this.countLabelOf,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 100),
  });

  Map<String, List<T>> _grouped() {
    final map = <String, List<T>>{};
    for (final item in items) {
      final subject = subjectOf(item).isNotEmpty ? subjectOf(item) : 'General';
      map.putIfAbsent(subject, () => []).add(item);
    }
    final sortedKeys = map.keys.toList()..sort();
    return {for (final key in sortedKeys) key: map[key]!};
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _grouped();

    return ListView(
      padding: padding,
      children: grouped.entries.map((entry) {
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ExpansionTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(
              '${entry.key} · ${countLabelOf(entry.value.length)}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            children: entry.value.map(itemBuilder).toList(),
          ),
        );
      }).toList(),
    );
  }
}
