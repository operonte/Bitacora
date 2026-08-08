import 'package:flutter/material.dart';
import '../../colors.dart';
import '../../models/career_model.dart';
import '../../models/subject_model.dart';
import '../../services/career_supabase_service.dart';

/// Materias de una carrera, dentro del panel de administración.
///
/// Antes era un `AlertDialog` con un `Column` sin scroll: con ocho materias ya
/// apretaba y con más se cortaba sin más. Y cada botón de editar o agregar lo
/// cerraba para abrir otro diálogo que, al terminar, no volvía — había que
/// reabrir la carrera desde cero por cada cambio.
///
/// Como pantalla, la lista tiene scroll y los diálogos se abren encima sin
/// perder de vista dónde estabas.
class CareerSubjectsScreen extends StatelessWidget {
  final Career career;

  const CareerSubjectsScreen({super.key, required this.career});

  static final CareerSupabaseService _service = CareerSupabaseService();

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

          final materias = actual.predefinedSubjects;
          if (materias.isEmpty) {
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

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: materias.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final materia = materias[i];
              return ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: Text(materia.name),
                subtitle: materia.professor.isEmpty
                    ? null
                    : Text(materia.professor),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
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
              );
            },
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
                name: nombreController.text.trim(),
                professor: profesorController.text.trim(),
                userId: 'system',
                userName: 'Sistema',
                createdAt: materia?.createdAt ?? DateTime.now(),
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
          const SnackBar(content: Text('Materia eliminada')),
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
