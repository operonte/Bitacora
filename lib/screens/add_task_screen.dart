import 'package:flutter/material.dart';
import '../utils/logger.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../services/supabase_db_service.dart';
import '../models/task_model.dart';
import '../models/subject_model.dart';
import '../notification_service.dart';
import '../colors.dart';
import 'subjects_screen.dart';
import '../utils/error_handler.dart';
import '../utils/validators.dart';
import '../utils/input_sanitizer.dart';
import '../models/career_model.dart';
import '../services/career_service.dart';
import '../providers/app_state.dart';

class AddTaskScreen extends StatefulWidget {
  final Task? task;

  const AddTaskScreen({super.key, this.task});

  @override
  State<AddTaskScreen> createState() => _AddTaskScreenState();
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

  /// Materias creadas por el usuario en "Mis Materias". No pertenecen a
  /// ninguna carrera, así que se ofrecen siempre.
  List<Subject> _ownSubjects = [];

  /// Cambia cuando la carrera invalida la materia elegida, para que el
  /// Autocomplete se reconstruya con el campo vacío.
  Key _subjectFieldKey = UniqueKey();

  bool _isLoading = false;
  final SupabaseDbService _supabaseService = SupabaseDbService();
  final CareerService _careerService = CareerService();
  Career? _selectedCareer;

  /// Quién ve la tarea. Privada por defecto: publicar al grupo tiene que ser
  /// una decisión, no la consecuencia de qué carrera estaba activa.
  bool _isShared = false;

  /// La lista vive en el modelo para que no vuelva a divergir: el formulario
  /// ofrecía 9 tipos y la validación aceptaba 11, así que una tarea creada en
  /// otra versión con 'laboratorio' era válida pero no se podía elegir al
  /// editarla.
  static const List<String> _taskTypes = Task.selectableTypes;

  @override
  void initState() {
    super.initState();
    // El orden importa: primero la carrera, porque de ella depende qué
    // asignaturas se ofrecen. Es la cascada carrera → asignatura.
    _initializeData();
    _rebuildSubjects();
    _loadSubjects();
  }

  /// Carreras entre las que se puede elegir. Nunca está vacía en la práctica:
  /// no se puede usar la app sin pertenecer a alguna.
  List<Career> get _careers => _careerService.getCareers();

  /// [_careers] sin las desactivadas, salvo que sea la ya elegida — para no
  /// reasignar en silencio una tarea existente a otra carrera al abrir el
  /// formulario. El servidor igual rechaza guardar en una carrera inactiva.
  List<Career> get _selectableCareers => _careers
      .where((c) => c.isActive || c.id == _selectedCareer?.id)
      .toList();

  void _initializeData() {
    // Al editar se respeta la carrera guardada en la tarea; al crear, la
    // activa como propuesta.
    final task = widget.task;
    if (task != null && task.careerId != null) {
      _selectedCareer = _careers.firstWhere(
        (c) => c.id == task.careerId,
        orElse: () =>
            _careerService.getSelectedCareer() ?? _careers.first,
      );
    } else {
      _selectedCareer = _careerService.getSelectedCareer();
    }

    if (task != null) {
      _isShared = task.isShared;
      _titleController.text = task.title;
      _descriptionController.text = task.description;
      _selectedSubject = task.subject;
      _selectedProfessor = task.professor;
      _professorController.text = task.professor;
      // Una tarea vieja puede traer 'presentacion' sin tilde, que se acepta
      // pero no está en el desplegable; sin esto el Dropdown revienta porque
      // su initialValue no calza con ningún item.
      _selectedType = _taskTypes.contains(task.type)
          ? task.type
          : (task.type == 'presentacion' ? 'presentación' : 'otro');
      _dueDate = task.dueDate;
      _dueTime = TimeOfDay.fromDateTime(task.dueDate);
      _isCompleted = task.isCompleted;
      _isSubmitted = task.isSubmitted;
      _tagController.text = task.tag ?? '';
      _collaboratorsController.text = task.collaborators.join(', ');
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

  /// Materias predefinidas de [career]. Mezclar las de todas las carreras era
  /// el origen del error que motivó esto: con Teología activa se podía elegir
  /// "Programación I" y la tarea terminaba publicada al grupo equivocado.
  ///
  /// Las inactivas (de un semestre anterior) no se ofrecen, salvo que sea la
  /// ya elegida — para no vaciar en silencio el campo al editar una tarea
  /// vieja. Siguen disponibles igual en Archivos/Material docente.
  List<Subject> _predefinedSubjectsFor(Career? career) {
    if (career == null) return [];
    var idx = 0;
    return career.predefinedSubjects
        .where((s) => s.isActive || s.name == _selectedSubject)
        .map((subject) {
      final index = idx++;
      return Subject(
        id: subject.id ?? 'predef_${career.id}_$index',
        name: subject.name,
        professor: subject.professor,
        description: subject.description,
        visibility: SubjectVisibility.soloYo,
        userId: subject.userId,
        userName: subject.userName,
        createdAt: subject.createdAt,
        isActive: subject.isActive,
      );
    }).toList();
  }

  /// Recalcula la lista ofrecida: las de la carrera elegida más las materias
  /// propias del usuario, que no pertenecen a ninguna carrera y por eso se
  /// muestran siempre.
  void _rebuildSubjects() {
    final predefined = _predefinedSubjectsFor(_selectedCareer);
    final names = predefined.map((s) => s.name.toLowerCase()).toSet();
    final propias =
        _ownSubjects.where((s) => !names.contains(s.name.toLowerCase()));

    _subjects = [...predefined, ...propias];
    _filteredSubjects = _subjects;

    // La materia elegida puede no existir en la carrera nueva.
    if (_selectedSubject.isNotEmpty &&
        !_subjects.any((s) => s.name == _selectedSubject)) {
      _selectedSubject = '';
      _selectedProfessor = '';
      _professorController.clear();
      _subjectFieldKey = UniqueKey(); // fuerza a repintar el Autocomplete
    }
  }

  Future<void> _loadSubjects() async {
    // Caché local primero, para que el formulario abra con algo.
    _ownSubjects = _supabaseService.getSubjectsFromCache();
    if (mounted) setState(_rebuildSubjects);

    try {
      _ownSubjects = await _supabaseService.getSubjects();
      if (!mounted) return;
      setState(_rebuildSubjects);
    } catch (e) {
      Logger.error('Error cargando materias desde Supabase: $e', tag: 'App');
      // Si falla, quedan las predefinidas de la carrera, que son locales.
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
                maxLength: 1500,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                maxLines: 3,
                validator: (value) =>
                    Validators.maxLength(value, 1500, 'La descripción'),
              ),
              const SizedBox(height: 16),
              // Carrera antes que asignatura, a propósito: la primera acota
              // las opciones de la segunda.
              DropdownButtonFormField<String>(
                initialValue:
                    _selectableCareers.any((c) => c.id == _selectedCareer?.id)
                        ? _selectedCareer?.id
                        : null,
                decoration: const InputDecoration(
                  labelText: 'Carrera',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.workspace_premium_outlined),
                  helperText: 'Define qué asignaturas puedes elegir',
                ),
                items: _selectableCareers
                    .map((c) => DropdownMenuItem<String>(
                          value: c.id,
                          child: Text(
                            c.isActive ? c.name : '${c.name} (inactiva)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Elige una carrera' : null,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _selectedCareer =
                        _careers.firstWhere((c) => c.id == value);
                    _rebuildSubjects();
                    // Autocomplete no vuelve a llamar a optionsBuilder solo
                    // porque _filteredSubjects cambió: si el campo de
                    // asignatura ya estaba vacío (tarea nueva), se quedaba
                    // mostrando las opciones de la carrera anterior hasta
                    // que el usuario tipeara algo. Cambiar la key fuerza a
                    // remontarlo con la lista ya actualizada.
                    _subjectFieldKey = UniqueKey();
                  });
                },
              ),
              const SizedBox(height: 16),
              Autocomplete<Subject>(
                key: _subjectFieldKey,
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
                        // No basta con que haya algo escrito: tiene que ser
                        // una materia de la carrera elegida o una propia. El
                        // campo es de texto para poder buscar entre muchas,
                        // pero escribir cualquier cosa creaba tareas colgando
                        // de asignaturas que no existen, y desde el
                        // endurecimiento 16 el servidor las rechaza.
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Por favor selecciona una asignatura';
                          }
                          final escrita = value.trim().toLowerCase();
                          final existe = _subjects
                              .any((s) => s.name.toLowerCase() == escrita);
                          if (!existe) {
                            return 'Elige una de la lista, o créala con el botón +';
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
                      title: const Text('Entregada'),
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
              const SizedBox(height: 8),
              // Antes toda tarea con carrera se publicaba al grupo, y la
              // carrera se heredaba de la que estuviera activa: se podía
              // compartir sin haberlo decidido. Ahora es explícito y privado
              // por defecto, igual que en reuniones.
              Card(
                margin: EdgeInsets.zero,
                child: SwitchListTile(
                  value: _isShared,
                  activeThumbColor: AppColors.primary,
                  secondary: Icon(
                    _isShared ? Icons.groups_outlined : Icons.lock_outline,
                    color: _isShared ? AppColors.primary : null,
                  ),
                  title: Text(_isShared ? 'Tarea compartida' : 'Tarea privada'),
                  subtitle: Text(
                    _isShared
                        ? 'La verán todos los miembros de '
                            '${_selectedCareer?.name ?? 'la carrera'}'
                        : 'Solo la ves tú',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onChanged: (v) => setState(() => _isShared = v),
                ),
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
    final now = DateTime.now();
    var first = DateTime(now.year, now.month, now.day);
    var last = now.add(const Duration(days: 365));

    // Al editar una tarea vencida su fecha original queda fuera del rango, y
    // el selector obligaba a inventar una fecha futura solo para corregir una
    // descripción — con lo que la tarea saltaba de Vencidas a Pendientes. Se
    // amplía el rango para incluir la fecha que ya tiene.
    if (_dueDate.isBefore(first)) first = _dueDate;
    if (_dueDate.isAfter(last)) last = _dueDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: first,
      lastDate: last,
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
      final user = Supabase.instance.client.auth.currentUser;

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

      final titleClean = InputSanitizer.sanitizeText(_titleController.text);
      final descClean = InputSanitizer.sanitizeText(_descriptionController.text);
      final professorClean = InputSanitizer.sanitizeText(_selectedProfessor);

      final task = Task(
        id: widget.task?.id,
        title: titleClean,
        description: descClean,
        subject: _selectedSubject,
        professor: professorClean,
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
        userId: user.id,
        userName: user.userMetadata?['full_name'] as String? ?? user.userMetadata?['name'] as String? ?? 'Usuario',
        createdAt: widget.task?.createdAt ?? DateTime.now(),
        careerId: _selectedCareer?.id,
        isShared: _isShared,
      );

      // Los avisos no se programan acá: addTask y updateTask ya llaman a
      // syncAllTaskReminders con la lista completa, que además recalcula el
      // resumen diario. Hacerlo también desde la pantalla dejaba las dos
      // cosas peleando por el mismo id.
      bool success;
      if (widget.task == null) {
        // Crear nueva tarea a través del AppState (notifica a todas las pantallas)
        success = await appState.addTask(task) != null;
      } else {
        // Actualizar a través del AppState
        success = await appState.updateTask(task);
      }

      if (!mounted) return;

      if (!success) {
        ErrorHandler.showErrorSnackBar(
          context,
          AppException(type: AppErrorType.unknown, message: appState.error),
        );
        setState(() => _isLoading = false);
        return;
      }

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
      final appException = ErrorMessages.fromBackendError(e);
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
                final appState = context.read<AppState>();
                final success = await appState.deleteTask(widget.task!.id!);

                if (!context.mounted) return;

                if (!success) {
                  ErrorHandler.showErrorSnackBar(
                    context,
                    AppException(type: AppErrorType.unknown, message: appState.error),
                  );
                  return;
                }

                final notificationService = NotificationService();
                await notificationService.cancelTaskReminders(widget.task!.id!);

                if (!context.mounted) return;
                Navigator.pop(context, true);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tarea eliminada')),
                );
              } catch (e) {
                if (context.mounted) {
                  final appException = ErrorMessages.fromBackendError(e);
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
