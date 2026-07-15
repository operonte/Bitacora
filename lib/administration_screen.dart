import 'package:flutter/material.dart';
import 'colors.dart';
import 'models/career_model.dart';
import 'subject_model.dart';
import 'services/career_firestore_service.dart';

/// Pantalla de administración para gestionar carreras y asignaturas.
///
/// Usa streams en tiempo real para mostrar cambios instantáneos.
class AdministrationScreen extends StatefulWidget {
  const AdministrationScreen({super.key});

  @override
  State<AdministrationScreen> createState() => _AdministrationScreenState();
}

class _AdministrationScreenState extends State<AdministrationScreen> {
  final CareerFirestoreService _careerService = CareerFirestoreService();

  void _showCreateCareerDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final accessKeyController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Crear Nueva Carrera'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la carrera *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El nombre es obligatorio';
                    }
                    if (value.trim().length < 3) {
                      return 'El nombre debe tener al menos 3 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción (opcional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: accessKeyController,
                  decoration: const InputDecoration(
                    labelText: 'Clave de acceso *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'La clave de acceso es obligatoria';
                    }
                    if (value.trim().length < 4) {
                      return 'La clave debe tener al menos 4 caracteres';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) {
                return;
              }

              final name = nameController.text.trim();
              final description = descriptionController.text.trim();
              final accessKey = accessKeyController.text.trim();

              final career = Career(
                id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                name: name,
                accessKey: accessKey,
                description: description.isEmpty ? null : description,
                predefinedSubjects: [],
              );

              try {
                await _careerService.createCareer(career);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Carrera creada exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al crear carrera: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  void _showEditCareerDialog(Career career) {
    final nameController = TextEditingController(text: career.name);
    final descriptionController = TextEditingController(
      text: career.description ?? '',
    );
    final accessKeyController = TextEditingController(text: career.accessKey);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Carrera'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la carrera *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El nombre es obligatorio';
                    }
                    if (value.trim().length < 3) {
                      return 'El nombre debe tener al menos 3 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción (opcional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: accessKeyController,
                  decoration: const InputDecoration(
                    labelText: 'Clave de acceso *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'La clave de acceso es obligatoria';
                    }
                    if (value.trim().length < 4) {
                      return 'La clave debe tener al menos 4 caracteres';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) {
                return;
              }

              final name = nameController.text.trim();
              final description = descriptionController.text.trim();
              final accessKey = accessKeyController.text.trim();

              final updatedCareer = Career(
                id: career.id,
                name: name,
                accessKey: accessKey,
                description: description.isEmpty ? null : description,
                predefinedSubjects: career.predefinedSubjects,
              );

              try {
                await _careerService.updateCareer(updatedCareer);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Carrera actualizada exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al actualizar carrera: $e'),
                      backgroundColor: Colors.red,
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
  }

  void _showDeleteCareerDialog(Career career) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Carrera'),
        content: Text(
          '¿Estás seguro de que deseas eliminar la carrera "${career.name}"? Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _careerService.deleteCareer(career.id);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Carrera eliminada exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al eliminar carrera: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  void _showCareerSubjects(Career career) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Materias de ${career.name}'),
        content: StreamBuilder<Career?>(
          stream: _careerService.getCareerStream(career.id),
          initialData: career,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final currentCareer = snapshot.data;
            if (currentCareer == null) {
              return const Text('Carrera no encontrada');
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (currentCareer.predefinedSubjects.isEmpty)
                  const Text('No hay materias registradas')
                else
                  ...currentCareer.predefinedSubjects.map(
                    (subject) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          const Text('• '),
                          Expanded(child: Text(subject.name)),
                          IconButton(
                            icon: const Icon(
                              Icons.edit,
                              size: 20,
                              color: Colors.blue,
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              _showEditSubjectDialog(currentCareer, subject);
                            },
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              size: 20,
                              color: Colors.red,
                            ),
                            onPressed: () {
                              Navigator.pop(context);
                              _showDeleteSubjectDialog(currentCareer, subject);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showAddSubjectDialog(currentCareer);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar Materia'),
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showAddSubjectDialog(Career career) {
    final nameController = TextEditingController();
    final professorController = TextEditingController();
    final descriptionController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Agregar Materia'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la materia *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El nombre de la materia es obligatorio';
                    }
                    if (value.trim().length < 3) {
                      return 'El nombre debe tener al menos 3 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: professorController,
                  decoration: const InputDecoration(
                    labelText: 'Profesor *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El nombre del profesor es obligatorio';
                    }
                    if (value.trim().length < 3) {
                      return 'El nombre debe tener al menos 3 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción (opcional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) {
                return;
              }

              final name = nameController.text.trim();
              final professor = professorController.text.trim();
              final description = descriptionController.text.trim();

              final subject = Subject(
                id: 'subject_${DateTime.now().millisecondsSinceEpoch}',
                name: name,
                professor: professor,
                description: description.isEmpty ? null : description,
                userId: 'admin',
                userName: 'Administrador',
                createdAt: DateTime.now(),
              );

              try {
                await _careerService.addSubjectToCareer(career.id, subject);
                if (context.mounted) {
                  // No cerramos el diálogo para permitir agregar más materias
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Materia agregada exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al agregar materia: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Agregar'),
          ),
        ],
      ),
    );
  }

  void _showEditSubjectDialog(Career career, Subject subject) {
    final nameController = TextEditingController(text: subject.name);
    final professorController = TextEditingController(text: subject.professor);
    final descriptionController = TextEditingController(
      text: subject.description ?? '',
    );
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Editar Materia'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nombre de la materia *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El nombre de la materia es obligatorio';
                    }
                    if (value.trim().length < 3) {
                      return 'El nombre debe tener al menos 3 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: professorController,
                  decoration: const InputDecoration(
                    labelText: 'Profesor *',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'El nombre del profesor es obligatorio';
                    }
                    if (value.trim().length < 3) {
                      return 'El nombre debe tener al menos 3 caracteres';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Descripción (opcional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) {
                return;
              }

              final name = nameController.text.trim();
              final professor = professorController.text.trim();
              final description = descriptionController.text.trim();

              final updatedSubject = Subject(
                id: subject.id,
                name: name,
                professor: professor,
                description: description.isEmpty ? null : description,
                userId: subject.userId,
                userName: subject.userName,
                createdAt: subject.createdAt,
              );

              try {
                // Primero eliminar la materia antigua y luego agregar la nueva
                await _careerService.removeSubjectFromCareer(
                  career.id,
                  subject.id ?? '',
                );
                await _careerService.addSubjectToCareer(
                  career.id,
                  updatedSubject,
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Materia actualizada exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al actualizar materia: $e'),
                      backgroundColor: Colors.red,
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
  }

  void _showDeleteSubjectDialog(Career career, Subject subject) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Materia'),
        content: Text(
          '¿Estás seguro de que deseas eliminar la materia "${subject.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await _careerService.removeSubjectFromCareer(
                  career.id,
                  subject.id ?? '',
                );
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Materia eliminada exitosamente'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al eliminar materia: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Administración'),
      ),
      body: StreamBuilder<List<Career>>(
        stream: _careerService.getCareersStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 80, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(
                    'Error al cargar carreras: ${snapshot.error}',
                    style: const TextStyle(fontSize: 16, color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {}); // Rebuild para reintentar
                    },
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            );
          }

          final careers = snapshot.data ?? [];

          if (careers.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.work_outline, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No hay carreras registradas',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: careers.length,
            itemBuilder: (context, index) {
              final career = careers[index];
              final isPredefined = Careers.all.any((c) => c.id == career.id);
              return Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  leading: const Icon(Icons.work, color: AppColors.primary),
                  title: Text(career.name),
                  subtitle: Text(
                    '${career.predefinedSubjects.length} materias${isPredefined ? ' (predefinida)' : ' (personalizada)'}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showEditCareerDialog(career),
                        tooltip: 'Editar',
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _showDeleteCareerDialog(career),
                        tooltip: 'Eliminar',
                      ),
                      const Icon(Icons.arrow_forward_ios),
                    ],
                  ),
                  onTap: () => _showCareerSubjects(career),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateCareerDialog,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
