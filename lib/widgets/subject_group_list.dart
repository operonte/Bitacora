import 'package:flutter/material.dart';

/// Lista de tarjetas plegables agrupadas por materia, con encabezado
/// "Materia · N <algo>" (ej. "Hebreo · 5 archivos"). Se usa en "Mis tareas"
/// (archivos), "Mis reuniones" y "Material docente" para que listas largas
/// no se vuelvan una sola columna interminable de tarjetas.
///
/// Si se provee [searchTextOf], muestra además una barra de búsqueda y las
/// carpetas con coincidencias quedan abiertas mientras dure la búsqueda.
class SubjectGroupList<T> extends StatefulWidget {
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

  /// Texto sobre el que busca la barra de búsqueda. Sin esto no hay barra.
  final String Function(T item)? searchTextOf;
  final String searchHint;

  /// Widget opcional fijo arriba de todo (ej. un filtro por carrera).
  final Widget? header;

  const SubjectGroupList({
    super.key,
    required this.items,
    required this.subjectOf,
    required this.itemBuilder,
    required this.countLabelOf,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 100),
    this.dateOf,
    this.dateDescending = false,
    this.searchTextOf,
    this.searchHint = 'Buscar',
    this.header,
  });

  @override
  State<SubjectGroupList<T>> createState() => _SubjectGroupListState<T>();
}

class _SubjectGroupListState<T> extends State<SubjectGroupList<T>> {
  /// Qué carpetas dejó abiertas el usuario. Vive en el State y no en cada
  /// ExpansionTile porque estas listas se reconstruyen seguido (van dentro de
  /// un ListenableBuilder) y si no, se cerraban solas.
  final Set<String> _expanded = {};
  String _query = '';

  List<T> get _filtered {
    final searchTextOf = widget.searchTextOf;
    final query = _query.trim().toLowerCase();
    if (searchTextOf == null || query.isEmpty) return widget.items;
    return widget.items
        .where((item) => searchTextOf(item).toLowerCase().contains(query))
        .toList();
  }

  Map<String, List<T>> _grouped(List<T> items) {
    final map = <String, List<T>>{};
    for (final item in items) {
      final subject =
          widget.subjectOf(item).isNotEmpty ? widget.subjectOf(item) : 'General';
      map.putIfAbsent(subject, () => []).add(item);
    }
    final sortedKeys = map.keys.toList();
    final dateOfFn = widget.dateOf;
    if (dateOfFn != null) {
      DateTime representativeOf(String key) {
        final dates = map[key]!.map(dateOfFn).whereType<DateTime>();
        if (dates.isEmpty) {
          return widget.dateDescending ? DateTime(0) : DateTime(9999);
        }
        return widget.dateDescending
            ? dates.reduce((a, b) => a.isAfter(b) ? a : b)
            : dates.reduce((a, b) => a.isBefore(b) ? a : b);
      }

      sortedKeys.sort((a, b) => widget.dateDescending
          ? representativeOf(b).compareTo(representativeOf(a))
          : representativeOf(a).compareTo(representativeOf(b)));

      for (final list in map.values) {
        list.sort((a, b) {
          final dateA = dateOfFn(a);
          final dateB = dateOfFn(b);
          if (dateA == null || dateB == null) return 0;
          return widget.dateDescending
              ? dateB.compareTo(dateA)
              : dateA.compareTo(dateB);
        });
      }
    } else {
      sortedKeys.sort();
    }
    return {for (final key in sortedKeys) key: map[key]!};
  }

  @override
  Widget build(BuildContext context) {
    final searching = _query.trim().isNotEmpty;
    final grouped = _grouped(_filtered);
    final entries = grouped.entries.toList();

    final hasSearch = widget.searchTextOf != null;
    final extraHeaders = (hasSearch ? 1 : 0) + (widget.header != null ? 1 : 0);

    return ListView.builder(
      padding: widget.padding,
      itemCount: entries.length + extraHeaders + (entries.isEmpty ? 1 : 0),
      itemBuilder: (context, index) {
        var offset = index;

        if (widget.header != null) {
          if (offset == 0) return widget.header!;
          offset--;
        }

        if (hasSearch) {
          if (offset == 0) return _buildSearchField();
          offset--;
        }

        if (entries.isEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Text(
              searching ? 'Sin resultados para "$_query"' : 'Nada por acá todavía',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          );
        }

        final entry = entries[offset];
        // Durante una búsqueda todo se abre: si no, el usuario ve carpetas
        // cerradas y no sabe dónde cayó la coincidencia.
        final isOpen = searching || _expanded.contains(entry.key);

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ExpansionTile(
            // La key incluye el estado abierto para que ExpansionTile se
            // reconstruya cuando cambia por búsqueda y no por un toque.
            key: ValueKey('${entry.key}-$isOpen'),
            initiallyExpanded: isOpen,
            onExpansionChanged: (open) {
              if (searching) return;
              setState(() {
                if (open) {
                  _expanded.add(entry.key);
                } else {
                  _expanded.remove(entry.key);
                }
              });
            },
            leading: const Icon(Icons.folder_outlined),
            title: Text(
              '${entry.key} · ${widget.countLabelOf(entry.value.length)}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            children: entry.value.map(widget.itemBuilder).toList(),
          ),
        );
      },
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        onChanged: (value) => setState(() => _query = value),
        decoration: InputDecoration(
          hintText: widget.searchHint,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
