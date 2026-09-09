import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../colors.dart';
import '../models/career_model.dart';
import '../models/task_model.dart';
import '../providers/app_state.dart';
import '../services/career_service.dart';
import '../services/teacher_subject_service.dart';
import '../utils/error_handler.dart';
import '../utils/input_sanitizer.dart';
import '../utils/validators.dart';
import 'add_task_screen.dart';
import 'teacher_subjects_screen.dart';

/// Crear/editar una tarea oficial, del lado del docente.
///
/// A diferencia de [AddTaskScreen] (pensada para un alumno y su propia
/// tarea), acá no hay "Realizada"/"Entregada" ni el switch privada/
/// compartida: un docente que asigna trabajo a su curso no tiene nada
/// personal que marcar, y la tarea siempre nace compartida y oficial — es
/// justamente lo que la hace visible para sus alumnos y evaluable después
/// desde el detalle de la tarea ("Quién la debe").
///
/// La asignatura se limita a lo que el propio docente declaró impartir
/// (Mi Perfil → Mis asignaturas), mismo criterio que ya usa
/// [AttendanceScreen] — así no puede asignar por error una tarea a una
/// materia que no es suya.
class AssignTaskScreen extends StatefulWidget {
  final Career career;
  final Task? task;

  const AssignTaskScreen({super.key, required this.career, this.task});

  /// La pantalla que corresponde abrir para editar [task]: esta, si es una
  /// tarea oficial de un docente que la ve; si no, `null` — quien llama cae
  /// entonces a [AddTaskScreen].
  static Widget? editorFor(Task task) {
    if (!task.isShared || !CareerService().isDocente(task.careerId)) {
      return null;
    }
    final careerId = task.careerId;
    if (careerId == null) return null;
    Career career;
    try {
      career = CareerService().getCareers().firstWhere((c) => c.id == careerId);
    } catch (_) {
      return null;
    }
    return AssignTaskScreen(career: career, task: task);
  }

  @override
  State<AssignTaskScreen> createState() => _AssignTaskScreenState();
}

class _AssignTaskScreenState extends State<AssignTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _subject;
  String _selectedType = 'trabajo';
  DateTime _dueDate = DateTime.now().add(const Duration(days: 7));
  TimeOfDay _dueTime = const TimeOfDay(hour: 23, minute: 59);

  /// `null` = usar el default de la app (2 horas antes).
  int? _reminderMinutes;
  static const List<int?> _reminderOptions = [
    null,
    30,
    60,
    120,
    360,
    720,
    1440,
  ];

  static const List<String> _taskTypes = Task.selectableTypes;

  List<String>? _subjects;
  String? _subjectsError;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final task = widget.task;
    if (task != null) {
      _titleController.text = task.title;
      _descriptionController.text = task.description;
      _subject = task.subject;
      _selectedType = _taskTypes.contains(task.type) ? task.type : 'otro';
      _dueDate = task.dueDate;
      _dueTime = TimeOfDay.fromDateTime(task.dueDate);
      _reminderMinutes = task.reminderMinutes;
    }
    _loadSubjects();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadSubjects() async {
    try {
      final subjects = await TeacherSubjectService.myTeachingSubjects(
        widget.career.id,
      );
      subjects.sort();
      if (!mounted) return;
      setState(() {
        _subjects = subjects;
        // Si se está editando una tarea de una materia que ya no está en la
        // lista (se sacó de Mis asignaturas), se sigue ofreciendo para no
        // vaciar el campo en silencio.
        if (_subject == null && subjects.isNotEmpty) {
          _subject = subjects.first;
        } else if (_subject != null && !subjects.contains(_subject)) {
          subjects.add(_subject!);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _subjects = const [];
        _subjectsError = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Asignar tarea — ${widget.career.name}'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final subjects = _subjects;
    if (subjects == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (subjects.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _subjectsError ??
                    'Todavía no marcaste qué asignaturas impartes en '
                        '${widget.career.name} — sin eso no hay a quién '
                        'asignarle una tarea.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          TeacherSubjectsScreen(career: widget.career),
                    ),
                  );
                  if (mounted) _loadSubjects();
                },
                icon: const Icon(Icons.menu_book_outlined, size: 18),
                label: const Text('Elegir mis asignaturas'),
              ),
            ],
          ),
        ),
      );
    }

    return Form(
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
              validator: (value) =>
                  Validators.requiredWithLengthRange(value, 3, 100, 'El título'),
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
            DropdownButtonFormField<String>(
              initialValue: subjects.contains(_subject) ? _subject : null,
              decoration: const InputDecoration(
                labelText: 'Asignatura',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.book),
                helperText: 'Solo las que impartes en esta carrera',
              ),
              items: subjects
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(s, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Elige una asignatura' : null,
              onChanged: (value) => setState(() => _subject = value),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedType,
              decoration: const InputDecoration(
                labelText: 'Tipo de tarea',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category),
              ),
              items: _taskTypes
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(type[0].toUpperCase() + type.substring(1)),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _selectedType = value!),
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
            DropdownButtonFormField<int?>(
              initialValue: _reminderMinutes,
              decoration: const InputDecoration(
                labelText: 'Avisar con anticipación',
                prefixIcon: Icon(Icons.notifications_outlined),
              ),
              items: _reminderOptions
                  .map(
                    (minutes) => DropdownMenuItem(
                      value: minutes,
                      child: Text(_reminderLabel(minutes)),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _reminderMinutes = v),
            ),
            const SizedBox(height: 8),
            const Text(
              'La van a ver todos tus alumnos de esta asignatura apenas la '
              'crees. Vas a poder ver quién la entregó desde el detalle de '
              'la tarea.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
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
                  : Text(widget.task == null ? 'Crear Tarea' : 'Actualizar Tarea'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDate() async {
    final now = DateTime.now();
    var first = DateTime(now.year, now.month, now.day);
    var last = now.add(const Duration(days: 365));
    if (_dueDate.isBefore(first)) first = _dueDate;
    if (_dueDate.isAfter(last)) last = _dueDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(context: context, initialTime: _dueTime);
    if (picked != null) setState(() => _dueTime = picked);
  }

  String _reminderLabel(int? minutes) {
    if (minutes == null) return '2 horas antes (por defecto)';
    if (minutes < 60) return '$minutes minutos antes';
    if (minutes < 1440) {
      final horas = minutes ~/ 60;
      return horas == 1 ? '1 hora antes' : '$horas horas antes';
    }
    return '1 día antes';
  }

  Future<void> _saveTask() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final appState = context.read<AppState>();
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Usuario no autenticado');

      final titleClean = InputSanitizer.sanitizeText(_titleController.text);
      final descClean = InputSanitizer.sanitizeText(_descriptionController.text);
      final userName =
          user.userMetadata?['full_name'] as String? ??
          user.userMetadata?['name'] as String? ??
          'Docente';

      final task = Task(
        id: widget.task?.id,
        title: titleClean,
        description: descClean,
        subject: _subject!,
        professor: userName,
        dueDate: DateTime(
          _dueDate.year,
          _dueDate.month,
          _dueDate.day,
          _dueTime.hour,
          _dueTime.minute,
        ),
        type: _selectedType,
        userId: user.id,
        userName: userName,
        createdAt: widget.task?.createdAt ?? DateTime.now(),
        careerId: widget.career.id,
        isShared: true,
        isOfficial: true,
        reminderMinutes: _reminderMinutes,
      );

      final success = widget.task == null
          ? await appState.addTask(task) != null
          : await appState.updateTask(task);

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
            widget.task == null ? '✓ Tarea asignada' : '✓ Tarea actualizada',
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
}
