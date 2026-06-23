import 'package:flutter/material.dart';
import 'utils/logger.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'firebase_service.dart';
import 'task_model.dart';
import 'subject_model.dart';
import 'notification_service.dart';
import 'colors.dart';
import 'subjects_screen.dart';
import 'utils/error_handler.dart';
import 'utils/validators.dart';
import 'models/career_model.dart';
import 'services/career_service.dart';
import 'providers/app_state.dart';

class AddTaskScreen extends StatefulWidget {
  final Task? task;

  const AddTaskScreen({super.key, this.task});

  @override
  _AddTaskScreenState createState() => _AddTaskScreenState();
}

class _AddTaskScreenState extends State<AddTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagController = TextEditingController();
  final _collaboratorsController = TextEditingController();
  final _professorController = TextEditingController();

  String _selectedSubject = '';
  String _selectedProfessor = '';
  String _selectedType = 'trabajo';
  DateTime _dueDate = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _dueTime = const TimeOfDay(hour: 23, minute: 59);
  bool _isCompleted = false;
  bool _isSubmitted = false;

  List<Subject> _subjects = [];
  List<Subject> _filteredSubjects = [];
  bool _isLoading = false;
  final FirebaseService _firebaseService = FirebaseService();
  final CareerService _careerService = CareerService();
  Career? _selectedCareer;

  final List<String> _taskTypes = [
    'trabajo',
    'resumen',
    'estudio',
    'prueba',
    'examen',
    'lectura',
    'ensayo',
    'presentación',
    'otro',
  ];

  @override
  void initState() {
    super.initState();
    // Cargar carrera de forma síncrona primero
    _loadCareerSync();
    // Luego cargar asignaturas
    _loadSubjects();
    // Finalmente inicializar datos de la tarea si es edición
    _initializeData();
  }

  void _loadCareerSync() {
    final career = _careerService.getSelectedCareer();
    if (career != null) {
      _selectedCareer = career;
    }
  }

  void _initializeData() {
    if (widget.task != null) {
      final task = widget.task!;
      _titleController.text = task.title;
      _descriptionController.text = task.description;
      _selectedSubject = task.subject;
      _selectedProfessor = task.professor;
      _professorController.text = task.professor;
      _selectedType = task.type;
      _dueDate = task.dueDate;
      _dueTime = TimeOfDay.fromDateTime(task.dueDate);
      _isCompleted = task.isCompleted;
      _isSubmitted = task.isSubmitted;
      _tagController.text = task.tag ?? '';
      _collaboratorsController.text = task.collaborators.join(', ');
      _filterSubjects('');
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagController.dispose();
    _collaboratorsController.dispose();
    _professorController.dispose();
    super.dispose();
  }

  Future<void> _loadSubjects() async {
    // Materias predefinidas según carrera seleccionada
    List<Subject> predefinedSubjects = [];

    if (_selectedCareer != null) {
      predefinedSubjects = _selectedCareer!.predefinedSubjects
          .asMap()
          .entries
          .map((entry) {
            final index = entry.key;
            final subject = entry.value;

            return Subject(
              id: subject.id ?? 'predef_${_selectedCareer!.id}_$index',
              name: subject.name,
              professor: subject.professor,
              description: subject.description,
              visibility: SubjectVisibility.soloYo,
              userId: subject.userId,
              userName: subject.userName,
              createdAt: subject.createdAt,
            );
          })
          .toList();
    } else {
      // Si no hay carrera seleccionada, cargar todas las materias predefinidas de todas las carreras
      predefinedSubjects = Careers.all
          .expand((career) => career.predefinedSubjects)
          .toList()
          .asMap()
          .entries
          .map((entry) {
            final index = entry.key;
            final subject = entry.value;

            return Subject(
              id: subject.id ?? 'predef_all_$index',
              name: subject.name,
              professor: subject.professor,
              description: subject.description,
              visibility: SubjectVisibility.soloYo,
              userId: subject.userId,
              userName: subject.userName,
              createdAt: subject.createdAt,
            );
          })
          .toList();
    }

    // Cargar primero desde caché local para respuesta inmediata
    final cachedSubjects = _firebaseService.getSubjectsFromCache();
    if (cachedSubjects.isNotEmpty) {
      setState(() {
        _subjects = [...predefinedSubjects, ...cachedSubjects];
        _filteredSubjects = _subjects;
      });
    }

    // Luego actualizar desde Firebase
    try {
      final firebaseSubjects = await _firebaseService.getSubjects();
      setState(() {
        _subjects = [...predefinedSubjects, ...firebaseSubjects];
        _filteredSubjects = _subjects;
      });
    } catch (e) {
      Logger.error('Error cargando materias desde Firebase: $e', tag: 'App');
      // Si falla, mantener las materias predefinidas y cache
    }

    // Si no hay materias en cache y falla Firebase, usar predefinidas
    if (_subjects.isEmpty) {
      setState(() {
        _subjects = predefinedSubjects;
        _filteredSubjects = _subjects;
      });
    }
  }

  void _filterSubjects(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredSubjects = _subjects;
      } else {
        _filteredSubjects = _subjects
            .where(
              (subject) =>
                  subject.name.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectedCareer != null
              ? 'Agregar Tarea - ${_selectedCareer!.name}'
              : (widget.task == null ? 'Nueva Tarea' : 'Editar Tarea'),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          if (widget.task != null)
            IconButton(icon: const Icon(Icons.delete), onPressed: _deleteTask),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Título de la tarea',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (value) => Validators.requiredWithLengthRange(
                  value,
                  3,
                  100,
                  'El título',
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 3,
                validator: (value) =>
                    Validators.maxLength(value, 1000, 'La descripción'),
              ),
              const SizedBox(height: 16),
              Autocomplete<Subject>(
                initialValue: TextEditingValue(text: _selectedSubject),
                optionsBuilder: (TextEditingValue textEditingValue) {
                  _filterSubjects(textEditingValue.text);
                  return _filteredSubjects.where(
                    (subject) => subject.name.toLowerCase().contains(
                      textEditingValue.text.toLowerCase(),
                    ),
                  );
                },
                displayStringForOption: (option) => option.name,
                onSelected: (Subject? selection) {
                  if (selection != null) {
                    setState(() {
                      _selectedSubject = selection.name;
                      _selectedProfessor = selection.professor;
                      _professorController.text = selection.professor;
                    });
                  }
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          labelText: 'Asignatura',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.book),
                          suffixIcon: IconButton(
                            icon: const Icon(
                              Icons.add_circle,
                              color: AppColors.primary,
                            ),
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const SubjectsScreen(),
                              ),
                            ),
                            tooltip: 'Agregar materia',
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Por favor selecciona una asignatura';
                          }
                          return null;
                        },
                        onChanged: (value) {
                          _selectedSubject = value;
                        },
                      );
                    },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _professorController,
                decoration: const InputDecoration(
                  labelText: 'Profesor',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                  helperText: 'Se completa automáticamente al elegir materia',
                ),
                onChanged: (value) {
                  _selectedProfessor = value;
                },
                validator: (value) =>
                    Validators.requiredWithMinLength(value, 2, 'El profesor'),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                decoration: const InputDecoration(
                  labelText: 'Tipo de tarea',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category),
                ),
                items: _taskTypes.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type[0].toUpperCase() + type.substring(1)),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedType = value!;
                  });
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _tagController,
                decoration: const InputDecoration(
                  labelText: 'Etiqueta (opcional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label),
                  hintText: 'Ej: examen, lectura, urgente',
                ),
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    return Validators.maxLength(value, 30, 'La etiqueta');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _collaboratorsController,
                decoration: const InputDecoration(
                  labelText: 'Colaboradores (opcional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.people),
                  hintText: 'Emails separados por coma',
                ),
                validator: (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    final emails = value
                        .split(',')
                        .map((e) => e.trim())
                        .toList();
                    for (final email in emails) {
                      final emailError = Validators.email(email);
                      if (emailError != null) {
                        return 'Email inválido: $email';
                      }
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _selectDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Fecha de entrega',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(DateFormat('dd/MM/yyyy').format(_dueDate)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      onTap: _selectTime,
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Hora de entrega',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.access_time),
                        ),
                        child: Text(_dueTime.format(context)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      title: const Text('Realizada'),
                      value: _isCompleted,
                      onChanged: (value) {
                        setState(() {
                          _isCompleted = value!;
                        });
                      },
                    ),
                  ),
                  Expanded(
                    child: CheckboxListTile(
                      title: const Text('Enviada'),
                      value: _isSubmitted,
                      onChanged: (value) {
                        setState(() {
                          _isSubmitted = value!;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _saveTask,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        widget.task == null
                            ? 'Crear Tarea'
                            : 'Actualizar Tarea',
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _dueDate = picked;
      });
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _dueTime,
    );
    if (picked != null) {
      setState(() {
        _dueTime = picked;
      });
    }
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final appState = context.read<AppState>();
      final notificationService = NotificationService();
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw Exception('Usuario no autenticado');
      }

      // Validar que se haya seleccionado asignatura y profesor
      if (_selectedSubject.isEmpty || _selectedProfessor.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Por favor selecciona una asignatura y profesor'),
          ),
        );
        setState(() => _isLoading = false);
        return;
      }

      final task = Task(
        id: widget.task?.id,
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim(),
        subject: _selectedSubject,
        professor: _selectedProfessor,
        dueDate: DateTime(
          _dueDate.year,
          _dueDate.month,
          _dueDate.day,
          _dueTime.hour,
          _dueTime.minute,
        ),
        type: _selectedType,
        isCompleted: _isCompleted,
        isSubmitted: _isSubmitted,
        userId: user.uid,
        userName: user.displayName ?? 'Usuario',
        tag: _tagController.text.trim().isEmpty
            ? null
            : _tagController.text.trim(),
        createdAt: widget.task?.createdAt ?? DateTime.now(),
        careerId: _selectedCareer?.id,
        collaborators: _collaboratorsController.text.trim().isEmpty
            ? []
            : _collaboratorsController.text
                  .split(',')
                  .map((e) => e.trim())
                  .toList(),
      );

      if (widget.task == null) {
        // Crear nueva tarea a través del AppState (notifica a todas las pantallas)
        await appState.addTask(task);
        // Obtener el ID real que asignó el AppState/Firebase
        final savedTask = appState.tasks
            .where(
              (t) => t.title == task.title && t.createdAt == task.createdAt,
            )
            .firstOrNull;

        if (savedTask != null) {
          await notificationService.scheduleTaskReminders(savedTask);
        }
      } else {
        // Actualizar a través del AppState
        await appState.updateTask(task);
        if (widget.task!.dueDate != task.dueDate) {
          await notificationService.cancelTaskReminders(task.id!);
          await notificationService.scheduleTaskReminders(task);
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.task == null ? '✓ Tarea creada' : '✓ Tarea actualizada',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final appException = ErrorMessages.fromFirebaseError(e);
      ErrorHandler.showErrorSnackBar(context, appException);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteTask() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Tarea'),
        content: const Text('¿Estás seguro de eliminar esta tarea?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);

              try {
                final firebaseService = FirebaseService();
                await firebaseService.deleteTask(widget.task!.id!);

                final notificationService = NotificationService();
                await notificationService.cancelTaskReminders(widget.task!.id!);

                if (!context.mounted) return;
                Navigator.pop(context, true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tarea eliminada')),
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
