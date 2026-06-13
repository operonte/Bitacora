import 'package:flutter/material.dart';
import 'firebase_service.dart';
import 'subject_model.dart';
import 'colors.dart';
import 'utils/error_handler.dart';
import 'utils/validators.dart';
import 'services/admin_auth_service.dart';

class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({super.key});

  @override
  _SubjectsScreenState createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  List<Subject> _subjects = [];
  bool _isLoading = true;
  final FirebaseService _firebaseService = FirebaseService();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final subjects = await _firebaseService.getSubjects();
      setState(() {
        _subjects = subjects;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        final appException = ErrorMessages.fromFirebaseError(e);
        ErrorHandler.showErrorSnackBar(context, appException);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Materias'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _subjects.isEmpty
          ? _buildEmptyState()
          : _buildSubjectsList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _addSubject,
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.school, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'No tienes materias registradas',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            'Agrega tus materias de universidad\nu otras actividades de estudio',
            style: TextStyle(fontSize: 14, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _addSubject,
            icon: const Icon(Icons.add),
            label: const Text('Agregar Materia'),
          ),
        ],
      ),
    );
  }

  Widget _buildSubjectsList() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _subjects.length,
        itemBuilder: (context, index) {
          final subject = _subjects[index];
          return _buildSubjectCard(subject);
        },
      ),
    );
  }

  Widget _buildSubjectCard(Subject subject) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.school, color: AppColors.primary),
        ),
        title: Text(
          subject.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Profesor: ${subject.professor}'),
            if (subject.description != null && subject.description!.isNotEmpty)
              Text(
                subject.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  subject.visibilityIcon,
                  size: 14,
                  color: subject.visibility == SubjectVisibility.soloYo
                      ? Colors.orange
                      : subject.visibility == SubjectVisibility.cursoCompleto
                      ? Colors.green
                      : Colors.blue,
                ),
                const SizedBox(width: 4),
                Text(
                  subject.visibilityText,
                  style: TextStyle(
                    fontSize: 12,
                    color: subject.visibility == SubjectVisibility.soloYo
                        ? Colors.orange
                        : subject.visibility == SubjectVisibility.cursoCompleto
                        ? Colors.green
                        : Colors.blue,
                  ),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'edit') {
              _editSubject(subject);
            } else if (value == 'delete') {
              _deleteSubject(subject);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 8),
                  Text('Editar'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Eliminar', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _addSubject() {
    _showPasswordDialog(() {
      _showSubjectDialog();
    });
  }

  void _showPasswordDialog(VoidCallback onVerified) {
    final passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Verificar Contraseña'),
        content: TextField(
          controller: passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Contraseña de administrador',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) async {
            final password = passwordController.text.trim();
            final isValid = await AdminAuthService.verifyPassword(password);
            if (!context.mounted) return;
            if (isValid) {
              Navigator.pop(context);
              onVerified();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('❌ Contraseña incorrecta'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              final password = passwordController.text.trim();
              final isValid = await AdminAuthService.verifyPassword(password);
              if (!context.mounted) return;
              if (isValid) {
                Navigator.pop(context);
                onVerified();
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('❌ Contraseña incorrecta'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('Verificar'),
          ),
        ],
      ),
    );
  }

  void _editSubject(Subject subject) {
    _showSubjectDialog(subject: subject);
  }

  void _showSubjectDialog({Subject? subject}) {
    final isEditing = subject != null;
    final nameController = TextEditingController(text: subject?.name ?? '');
    final professorController = TextEditingController(
      text: subject?.professor ?? '',
    );
    final descriptionController = TextEditingController(
      text: subject?.description ?? '',
    );
    SubjectVisibility visibility =
        subject?.visibility ?? SubjectVisibility.soloYo;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(isEditing ? 'Editar Materia' : 'Nueva Materia'),
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
                        hintText: 'Ej: Hermenéutica Bíblica',
                        prefixIcon: Icon(Icons.school),
                      ),
                      validator: (value) => Validators.requiredWithLengthRange(
                        value,
                        3,
                        100,
                        'El nombre',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: professorController,
                      decoration: const InputDecoration(
                        labelText: 'Profesor *',
                        hintText: 'Ej: Lic. Carlos Caamaño',
                        prefixIcon: Icon(Icons.person),
                      ),
                      validator: (value) => Validators.requiredWithMinLength(
                        value,
                        2,
                        'El profesor',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Descripción (opcional)',
                        hintText: 'Ej: Curso de 2do año, turno mañana',
                        prefixIcon: Icon(Icons.description),
                      ),
                      maxLines: 2,
                      validator: (value) =>
                          Validators.maxLength(value, 200, 'La descripción'),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<SubjectVisibility>(
                      initialValue: visibility,
                      decoration: const InputDecoration(
                        labelText: 'Visibilidad *',
                        prefixIcon: Icon(Icons.visibility),
                        border: OutlineInputBorder(),
                      ),
                      items: SubjectVisibility.values.map((v) {
                        return DropdownMenuItem(
                          value: v,
                          child: Row(
                            children: [
                              Icon(
                                v == SubjectVisibility.soloYo
                                    ? Icons.lock
                                    : v == SubjectVisibility.cursoCompleto
                                    ? Icons.public
                                    : Icons.people,
                                size: 20,
                                color: v == SubjectVisibility.soloYo
                                    ? Colors.orange
                                    : v == SubjectVisibility.cursoCompleto
                                    ? Colors.green
                                    : Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                v == SubjectVisibility.soloYo
                                    ? 'Solo yo'
                                    : v == SubjectVisibility.cursoCompleto
                                    ? 'Curso completo'
                                    : 'Elegir usuarios',
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            visibility = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        visibility == SubjectVisibility.soloYo
                            ? 'Solo tú podrás ver esta materia y usarla en tus tareas.'
                            : visibility == SubjectVisibility.cursoCompleto
                            ? 'Todos los usuarios podrán ver esta materia.'
                            : 'Podrás elegir qué usuarios específicos verán esta materia.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
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

                  Navigator.pop(context);

                  try {
                    final user = _firebaseService.currentUser;
                    if (user == null) throw Exception('Usuario no autenticado');

                    final newSubject = Subject(
                      id: subject?.id,
                      name: nameController.text.trim(),
                      professor: professorController.text.trim(),
                      description: descriptionController.text.trim().isEmpty
                          ? null
                          : descriptionController.text.trim(),
                      visibility: visibility,
                      userId: user.uid,
                      userName: user.displayName ?? 'Usuario',
                      createdAt: subject?.createdAt ?? DateTime.now(),
                    );

                    if (isEditing) {
                      await _firebaseService.updateSubject(newSubject);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Materia actualizada')),
                      );
                    } else {
                      await _firebaseService.addSubject(newSubject);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Materia agregada')),
                      );
                    }

                    _loadData();
                  } catch (e) {
                    if (context.mounted) {
                      final appException = ErrorMessages.fromFirebaseError(e);
                      ErrorHandler.showErrorSnackBar(context, appException);
                    }
                  }
                },
                child: Text(isEditing ? 'Guardar' : 'Agregar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _deleteSubject(Subject subject) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Materia'),
        content: Text(
          '¿Estás seguro de eliminar "${subject.name}"?\n\nLas tareas asociadas a esta materia no se eliminarán, pero aparecerán sin materia asignada.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _firebaseService.deleteSubject(subject.id!);
                _loadData();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Materia eliminada')),
                );
              } catch (e) {
                if (context.mounted) {
                  final appException = ErrorMessages.fromFirebaseError(e);
                  ErrorHandler.showErrorSnackBar(context, appException);
                }
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
