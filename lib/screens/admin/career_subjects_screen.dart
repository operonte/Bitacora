import 'package:flutter/material.dart';
import '../../colors.dart';
import '../../models/career_model.dart';
import '../../models/subject_model.dart';
import '../../services/career_supabase_service.dart';
import '../../utils/input_sanitizer.dart';

/// Materias de una carrera, dentro del panel de administración.
///
/// Antes era un `AlertDialog` con un `Column` sin scroll: con ocho materias ya
/// apretaba y con más se cortaba sin más. Y cada botón de editar o agregar lo
/// cerraba para abrir otro diálogo que, al terminar, no volvía — había que
/// reabrir la carrera desde cero por cada cambio.
///
/// Como pantalla, la lista tiene scroll y los diálogos se abren encima sin
/// perder de vista dónde estabas.
class CareerSubjectsScreen extends StatefulWidget {
  final Career career;

  const CareerSubjectsScreen({super.key, required this.career});

  @override
  State<CareerSubjectsScreen> createState() => _CareerSubjectsScreenState();
}

enum _EstadoFiltro { todas, activas, inactivas }

class _CareerSubjectsScreenState extends State<CareerSubjectsScreen> {
  final CareerSupabaseService _service = CareerSupabaseService();
  final _searchController = TextEditingController();
  String _query = '';

  /// null = "Todas". Con 62 materias en Teología (4 años × 2 semestres),
  /// buscar por texto no alcanzaba para ubicar rápido un semestre entero.
  String? _semestreSeleccionado;
  _EstadoFiltro _estadoFiltro = _EstadoFiltro.todas;
  bool _aplicandoEnBloque = false;

  Career get career => widget.career;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Materias que calzan con el texto, el semestre y el estado elegidos (las
  /// tres condiciones se combinan), por orden alfabético.
  ///
  /// Venían en el orden en que se agregaron, que con ocho ya obliga a leerlas
  /// todas para encontrar una — con 62 mucho más.
  List<Subject> _filtrar(List<Subject> materias) {
    final q = _query.trim().toLowerCase();
    final lista = materias.where((s) {
      final matchesQuery = q.isEmpty ||
          s.name.toLowerCase().contains(q) ||
          s.professor.toLowerCase().contains(q) ||
          (s.semester ?? '').toLowerCase().contains(q);
      final matchesSemestre = _semestreSeleccionado == null ||
          s.semester == _semestreSeleccionado;
      final matchesEstado = switch (_estadoFiltro) {
        _EstadoFiltro.todas => true,
        _EstadoFiltro.activas => s.isActive,
        _EstadoFiltro.inactivas => !s.isActive,
      };
      return matchesQuery && matchesSemestre && matchesEstado;
    }).toList();
    lista.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return lista;
  }

  /// Valores distintos de [Subject.semester] presentes en [materias],
  /// ordenados alfabéticamente. Vacío si nadie cargó un semestre todavía
  /// (ej. carreras chicas como Informática) — ahí no se muestra el chip-row.
  List<String> _semestresDisponibles(List<Subject> materias) {
    final valores = materias
        .map((s) => (s.semester ?? '').trim())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    valores.sort();
    return valores;
  }

  /// Chip "Todas" + uno por cada semestre distinto. Nada si la carrera no
  /// tiene ningún semestre cargado — mismo criterio que el filtro de
  /// materia en pending_tasks_screen.dart.
  Widget _buildSemestreChips(List<Subject> materias) {
    final semestres = _semestresDisponibles(materias);
    if (semestres.isEmpty) return const SizedBox.shrink();

    final opciones = ['Todas', ...semestres];
    return SizedBox(
      height: 44,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: opciones.length,
        itemBuilder: (context, index) {
          final opcion = opciones[index];
          final esTodas = opcion == 'Todas';
          final seleccionado =
              esTodas ? _semestreSeleccionado == null : _semestreSeleccionado == opcion;
          final primaryColor = Theme.of(context).primaryColor;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(
                opcion,
                style: TextStyle(
                  color: seleccionado
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight: seleccionado ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              selected: seleccionado,
              onSelected: (_) => setState(
                () => _semestreSeleccionado = esTodas ? null : opcion,
              ),
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkSurface
                  : Colors.grey[200],
              selectedColor: primaryColor,
              checkmarkColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: seleccionado ? primaryColor : AppColors.borderLight,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// "Todas / Activas / Inactivas". Siempre visible, no depende de los datos.
  Widget _buildEstadoChips() {
    const opciones = {
      _EstadoFiltro.todas: 'Todas',
      _EstadoFiltro.activas: 'Activas',
      _EstadoFiltro.inactivas: 'Inactivas',
    };
    final primaryColor = Theme.of(context).primaryColor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Wrap(
        spacing: 8,
        children: opciones.entries.map((entry) {
          final seleccionado = _estadoFiltro == entry.key;
          return FilterChip(
            label: Text(
              entry.value,
              style: TextStyle(
                color: seleccionado
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: seleccionado ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            selected: seleccionado,
            onSelected: (_) => setState(() => _estadoFiltro = entry.key),
            backgroundColor: Theme.of(context).brightness == Brightness.dark
                ? AppColors.darkSurface
                : Colors.grey[200],
            selectedColor: primaryColor,
            checkmarkColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: seleccionado ? primaryColor : AppColors.borderLight,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Botones para activar/desactivar de una vez todas las materias del
  /// semestre elegido. Pensado para el cambio de semestre: en vez de tocar
  /// ~8-16 switches uno por uno, dos toques con confirmación.
  Widget _buildAccionEnBloque(Career actual, String semestre) {
    final delSemestre =
        actual.predefinedSubjects.where((s) => s.semester == semestre).toList();
    final inactivas = delSemestre.where((s) => !s.isActive).length;
    final activas = delSemestre.length - inactivas;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _aplicandoEnBloque || inactivas == 0
                  ? null
                  : () => _confirmarEnBloque(actual, semestre, true, inactivas),
              icon: const Icon(Icons.toggle_on_outlined, size: 18),
              label: Text('Activar todas ($inactivas)'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _aplicandoEnBloque || activas == 0
                  ? null
                  : () => _confirmarEnBloque(actual, semestre, false, activas),
              icon: const Icon(Icons.toggle_off_outlined, size: 18),
              label: Text('Desactivar todas ($activas)'),
              style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarEnBloque(
    Career actual,
    String semestre,
    bool activar,
    int cantidad,
  ) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(activar ? 'Activar semestre' : 'Desactivar semestre'),
        content: Text(
          '${activar ? "Activar" : "Desactivar"} $cantidad materia'
          '${cantidad == 1 ? '' : 's'} de "$semestre".\n\n'
          '${activar ? "Van a ofrecerse" : "Van a dejar de ofrecerse"} para '
          'tareas y reuniones nuevas. Lo ya guardado con estas materias no '
          'cambia.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmado != true) return;
    await _aplicarEnBloque(actual, semestre, activar);
  }

  Future<void> _aplicarEnBloque(
    Career actual,
    String semestre,
    bool activar,
  ) async {
    final afectadas = actual.predefinedSubjects
        .where((s) => s.semester == semestre && s.isActive != activar)
        .toList();

    setState(() => _aplicandoEnBloque = true);
    try {
      // Secuencial a propósito: updateSubjectInCareer reescribe el array
      // entero cada vez (fetch-modifica-guarda). En paralelo, dos llamadas
      // podrían pisarse la una a la otra con datos viejos.
      for (final materia in afectadas) {
        await _service.updateSubjectInCareer(
          actual.id,
          materia.copyWith(isActive: activar),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${afectadas.length} materia${afectadas.length == 1 ? '' : 's'} '
              '${activar ? "activadas" : "desactivadas"}',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo aplicar a todas: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _aplicandoEnBloque = false);
    }
  }

  /// "Segundo Año · Sem. IV · Mg. X — inactiva". Cada parte solo aparece si
  /// hay dato; para ubicar de un vistazo a qué semestre pertenece cada
  /// materia sin tener que abrirla a editar.
  String _subtitulo(Subject materia) {
    final partes = <String>[
      if ((materia.semester ?? '').trim().isNotEmpty) materia.semester!.trim(),
      if (materia.professor.isNotEmpty) materia.professor,
    ];
    var texto = partes.join(' · ');
    if (!materia.isActive) {
      texto = texto.isEmpty ? 'Inactiva' : '$texto — inactiva';
    }
    return texto;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Materias de ${career.name}')),
      body: StreamBuilder<Career?>(
        stream: _service.getCareerStream(career.id),
        initialData: career,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final actual = snapshot.data;
          if (actual == null) {
            return const Center(child: Text('Carrera no encontrada'));
          }

          final materias = _filtrar(actual.predefinedSubjects);
          if (actual.predefinedSubjects.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Esta carrera todavía no tiene materias.\n'
                  'Agrégalas para que aparezcan al crear tareas, reuniones y '
                  'archivos.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary, height: 1.5),
                ),
              ),
            );
          }

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Buscar materia o profesor',
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            tooltip: 'Limpiar',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              _buildSemestreChips(actual.predefinedSubjects),
              _buildEstadoChips(),
              if (_semestreSeleccionado != null)
                _buildAccionEnBloque(actual, _semestreSeleccionado!),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${materias.length} materia${materias.length == 1 ? '' : 's'}'
                    ' · ${materias.where((s) => s.isActive).length} activas',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
              if (materias.isEmpty)
                const Expanded(
                  child: Center(child: Text('Ninguna materia calza')),
                )
              else
                Expanded(
                  child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: materias.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final materia = materias[i];
              return Opacity(
                opacity: materia.isActive ? 1 : 0.6,
                child: ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(materia.name),
                subtitle: Text(_subtitulo(materia)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: materia.isActive,
                      onChanged: (_) => _toggleActive(actual, materia),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      tooltip: 'Editar',
                      onPressed: () => _editar(context, actual, materia),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 20, color: AppColors.error),
                      tooltip: 'Eliminar',
                      onPressed: () => _eliminar(context, actual, materia),
                    ),
                  ],
                ),
                ),
              );
            },
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _agregar(context),
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 4,
        shape: const CircleBorder(),
        tooltip: 'Agregar materia',
        child: const Icon(Icons.add, color: Colors.white, size: 26),
      ),
    );
  }

  Future<void> _agregar(BuildContext context) =>
      _formulario(context, career, null);

  Future<void> _editar(
    BuildContext context,
    Career actual,
    Subject materia,
  ) =>
      _formulario(context, actual, materia);

  /// Activa o desactiva la materia. Desactivada, sigue disponible en
  /// Archivos/Material docente (para lo de semestres anteriores) pero deja de
  /// ofrecerse al crear tareas o reuniones nuevas.
  Future<void> _toggleActive(Career actual, Subject materia) async {
    try {
      await _service.updateSubjectInCareer(
        actual.id,
        materia.copyWith(isActive: !materia.isActive),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo cambiar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Un único formulario para crear y para editar: los dos diálogos separados
  /// que había eran el mismo campo por campo.
  Future<void> _formulario(
    BuildContext context,
    Career actual,
    Subject? materia,
  ) async {
    final esNueva = materia == null;
    final nombreController = TextEditingController(text: materia?.name ?? '');
    final profesorController =
        TextEditingController(text: materia?.professor ?? '');
    final semestreController =
        TextEditingController(text: materia?.semester ?? '');
    final formKey = GlobalKey<FormState>();

    final guardada = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(esNueva ? 'Agregar materia' : 'Editar materia'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nombreController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Nombre *',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => (val == null || val.trim().length < 2)
                    ? 'Mínimo 2 caracteres'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: profesorController,
                decoration: const InputDecoration(
                  labelText: 'Profesor',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: semestreController,
                decoration: const InputDecoration(
                  labelText: 'Semestre (opcional)',
                  hintText: 'Ej: Segundo Año · Sem. IV',
                  border: OutlineInputBorder(),
                  helperText: 'Solo para ubicarla en este panel',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;

              final nueva = Subject(
                id: materia?.id ??
                    'subj_${DateTime.now().millisecondsSinceEpoch}',
                name: InputSanitizer.sanitizeText(nombreController.text),
                professor:
                    InputSanitizer.sanitizeText(profesorController.text),
                userId: 'system',
                userName: 'Sistema',
                createdAt: materia?.createdAt ?? DateTime.now(),
                isActive: materia?.isActive ?? true,
                semester: semestreController.text.trim().isEmpty
                    ? null
                    : InputSanitizer.sanitizeText(semestreController.text),
              );

              try {
                if (esNueva) {
                  await _service.addSubjectToCareer(actual.id, nueva);
                } else {
                  await _service.updateSubjectInCareer(actual.id, nueva);
                }
                if (ctx.mounted) Navigator.pop(ctx, true);
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('No se pudo guardar: $e'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    nombreController.dispose();
    profesorController.dispose();
    semestreController.dispose();

    if (guardada == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(esNueva ? 'Materia agregada' : 'Materia actualizada'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _eliminar(
    BuildContext context,
    Career actual,
    Subject materia,
  ) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿Eliminar materia?'),
        content: Text(
          '"${materia.name}" dejará de aparecer al crear tareas, reuniones y '
          'archivos de ${actual.name}.\n\n'
          'Lo que ya esté guardado con esa materia no se borra ni cambia.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    try {
      await _service.removeSubjectFromCareer(actual.id, materia.id!);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${materia.name}" eliminada'),
            // La materia se conserva entera en memoria, así que devolverla es
            // volver a agregarla con los mismos datos. Es barato y evita que
            // un toque de más obligue a reescribir el nombre y el profesor.
            action: SnackBarAction(
              label: 'Deshacer',
              onPressed: () =>
                  _service.addSubjectToCareer(actual.id, materia),
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No se pudo eliminar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
