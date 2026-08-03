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
  /// Si se provee, las carpetas se ordenan por fecha en vez de
  /// alfabéticamente por materia: la fecha representativa de cada carpeta es
  /// la más próxima (ascendente, ej. reuniones) o la más reciente
  /// (descendente, ej. archivos recién subidos) entre sus items, según
  /// [dateDescending].
  final DateTime? Function(T item)? dateOf;
  final bool dateDescending;

  const SubjectGroupList({
    super.key,
    required this.items,
    required this.subjectOf,
    required this.itemBuilder,
    required this.countLabelOf,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 100),
    this.dateOf,
    this.dateDescending = false,
  });

  Map<String, List<T>> _grouped() {
    final map = <String, List<T>>{};
    for (final item in items) {
      final subject = subjectOf(item).isNotEmpty ? subjectOf(item) : 'General';
      map.putIfAbsent(subject, () => []).add(item);
    }
    final sortedKeys = map.keys.toList();
    final dateOfFn = dateOf;
    if (dateOfFn != null) {
      DateTime representativeOf(String key) {
        final dates = map[key]!.map(dateOfFn).whereType<DateTime>();
        if (dates.isEmpty) {
          return dateDescending ? DateTime(0) : DateTime(9999);
        }
        return dateDescending
            ? dates.reduce((a, b) => a.isAfter(b) ? a : b)
            : dates.reduce((a, b) => a.isBefore(b) ? a : b);
      }

      sortedKeys.sort((a, b) => dateDescending
          ? representativeOf(b).compareTo(representativeOf(a))
          : representativeOf(a).compareTo(representativeOf(b)));

      for (final list in map.values) {
        list.sort((a, b) {
          final dateA = dateOfFn(a);
          final dateB = dateOfFn(b);
          if (dateA == null || dateB == null) return 0;
          return dateDescending ? dateB.compareTo(dateA) : dateA.compareTo(dateB);
        });
      }
    } else {
      sortedKeys.sort();
    }
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
