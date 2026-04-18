import 'package:flutter/material.dart';
import 'firebase_service.dart';
import 'subject_model.dart';
import 'colors.dart';

class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({Key? key}) : super(key: key);

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar materias: $e')),
      );
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
            color: AppColors.primary.withOpacity(0.1),
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
                  subject.isPublic ? Icons.public : Icons.lock,
                  size: 14,
                  color: subject.isPublic ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 4),
                Text(
                  subject.isPublic ? 'Pública' : 'Privada',
                  style: TextStyle(
                    fontSize: 12,
                    color: subject.isPublic ? Colors.green : Colors.orange,
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
    _showSubjectDialog();
  }

  void _editSubject(Subject subject) {
    _showSubjectDialog(subject: subject);
  }

  void _showSubjectDialog({Subject? subject}) {
    final isEditing = subject != null;
    final nameController = TextEditingController(text: subject?.name ?? '');
    final professorController = TextEditingController(text: subject?.professor ?? '');
    final descriptionController = TextEditingController(text: subject?.description ?? '');
    bool isPublic = subject?.isPublic ?? false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(isEditing ? 'Editar Materia' : 'Nueva Materia'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la materia *',
                      hintText: 'Ej: Hermenéutica Bíblica',
                      prefixIcon: Icon(Icons.school),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: professorController,
                    decoration: const InputDecoration(
                      labelText: 'Profesor *',
                      hintText: 'Ej: Lic. Carlos Caamaño',
                      prefixIcon: Icon(Icons.person),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Descripción (opcional)',
                      hintText: 'Ej: Curso de 2do año, turno mañana',
                      prefixIcon: Icon(Icons.description),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Visibilidad'),
                    subtitle: Text(
                      isPublic
                          ? 'Pública: otros pueden ver esta materia'
                          : 'Privada: solo tú puedes ver esta materia',
                    ),
                    value: isPublic,
                    onChanged: (value) {
                      setDialogState(() {
                        isPublic = value;
                      });
                    },
                    secondary: Icon(
                      isPublic ? Icons.public : Icons.lock,
                      color: isPublic ? Colors.green : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (nameController.text.trim().isEmpty ||
                      professorController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Nombre y profesor son obligatorios'),
                        backgroundColor: Colors.red,
                      ),
                    );
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
                      isPublic: isPublic,
                      userId: user.uid,
                      userName: user.displayName ?? 'Usuario',
                      createdAt: subject?.createdAt ?? DateTime.now(),
                    );

                    if (isEditing) {
                      await _firebaseService.updateSubject(newSubject);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Materia actualizada')),
                      );
                    } else {
                      await _firebaseService.addSubject(newSubject);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Materia agregada')),
                      );
                    }

                    _loadData();
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
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
        content: Text('¿Estás seguro de eliminar "${subject.name}"?\n\nLas tareas asociadas a esta materia no se eliminarán, pero aparecerán sin materia asignada.'),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Materia eliminada')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error al eliminar: $e')),
                );
              }
            },
            child: const Text('Eliminar', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
