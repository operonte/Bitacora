import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/meeting_model.dart';
import '../services/meeting_service.dart';
import '../services/career_service.dart';
import '../services/supabase_db_service.dart';
import '../models/subject_model.dart';
import '../colors.dart';
import '../utils/validators.dart';
import '../utils/input_sanitizer.dart';

class AddMeetingScreen extends StatefulWidget {
  final Meeting? meeting;
  const AddMeetingScreen({super.key, this.meeting});

  @override
  State<AddMeetingScreen> createState() => _AddMeetingScreenState();
}

class _AddMeetingScreenState extends State<AddMeetingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _professorController = TextEditingController();
  final _linkController = TextEditingController();

  String _selectedSubject = '';
  String _selectedType = 'Zoom';

  /// Carrera a la que pertenece la reunión. null = "Sin carrera". Antes se
  /// tomaba en silencio de la carrera activa al guardar y no había forma de
  /// corregirla; ahora se elige acá y por eso se pueden reasignar las que ya
  /// existen simplemente editándolas.
  String? _selectedCareerId;

  bool _isRecurrent = false;
  DateTime _meetingDate = DateTime.now().add(const Duration(hours: 2));
  TimeOfDay _meetingTime = const TimeOfDay(hour: 14, minute: 0);

  bool _isLoading = false;
  List<Subject> _subjects = [];
  List<Subject> _filteredSubjects = [];

  final List<String> _meetingTypes = [
    'Zoom',
    'Google Meet',
    'Microsoft Teams',
    'Presencial',
    'Otro',
  ];

  @override
  void initState() {
    super.initState();
    _loadSubjects();
    _initData();
    _linkController.addListener(_onLinkChanged);
  }

  void _onLinkChanged() {
    final text = _linkController.text.toLowerCase();
    if (text.contains('zoom.us') || text.contains('zoom.com')) {
      if (_selectedType != 'Zoom') setState(() => _selectedType = 'Zoom');
    } else if (text.contains('meet.google.com')) {
      if (_selectedType != 'Google Meet') setState(() => _selectedType = 'Google Meet');
    } else if (text.contains('teams.microsoft.com') || text.contains('teams.live.com')) {
      if (_selectedType != 'Microsoft Teams') setState(() => _selectedType = 'Microsoft Teams');
    }
  }

  @override
  void dispose() {
    _linkController.removeListener(_onLinkChanged);
    _titleController.dispose();
    _descriptionController.dispose();
    _professorController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  void _initData() {
    if (widget.meeting != null) {
      final m = widget.meeting!;
      _titleController.text = m.title;
      _descriptionController.text = m.description;
      _selectedSubject = m.subject;
      _professorController.text = m.professor;
      _selectedType = m.type;
      _isRecurrent = m.isRecurrent;
      _linkController.text = m.meetingLink ?? '';
      _meetingDate = m.meetingDate;
      _meetingTime = TimeOfDay.fromDateTime(m.meetingDate);
      // Solo aceptar la carrera guardada si el usuario sigue perteneciendo a
      // ella; si no, el Dropdown recibiría un value que no está entre sus
      // items y Flutter lanza.
      final saved = m.careerId;
      final known = CareerService().careerIds;
      _selectedCareerId = (saved != null && known.contains(saved)) ? saved : null;
    } else {
      _selectedCareerId = CareerService().getSelectedCareer()?.id;
    }
  }

  Widget _buildCareerField() {
    final careers = CareerService().getCareers();
    if (careers.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String?>(
        initialValue: _selectedCareerId,
        decoration: const InputDecoration(
          labelText: 'Carrera',
          prefixIcon: Icon(Icons.school_outlined),
          border: OutlineInputBorder(),
          helperText: 'Sirve para filtrar las reuniones en Mi área',
        ),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('Sin carrera'),
          ),
          for (final c in careers)
            DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
        ],
        onChanged: (value) => setState(() => _selectedCareerId = value),
      ),
    );
  }

  Future<void> _loadSubjects() async {
    final careers = CareerService().getCareers();
    final user = Supabase.instance.client.auth.currentUser;
    final uId = user?.id ?? '';
    final uName = user?.email ?? 'Usuario';

    List<Subject> predefined = [];
    int counter = 0;
    for (final career in careers) {
      for (final s in career.predefinedSubjects) {
        predefined.add(Subject(
          id: 'pred_${counter++}',
          name: s.name,
          professor: s.professor,
          userId: uId,
          userName: uName,
          createdAt: DateTime.now(),
        ));
      }
    }

    try {
      final dbSubjects = await SupabaseDbService().getSubjects();
      if (mounted) {
        setState(() {
          final Map<String, Subject> uniqueMap = {};
          for (final s in [...predefined, ...dbSubjects]) {
            if (!uniqueMap.containsKey(s.name.toLowerCase())) {
              uniqueMap[s.name.toLowerCase()] = s;
            }
          }
          _subjects = uniqueMap.values.toList();
          _filteredSubjects = _subjects;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          final Map<String, Subject> uniqueMap = {};
          for (final s in predefined) {
            if (!uniqueMap.containsKey(s.name.toLowerCase())) {
              uniqueMap[s.name.toLowerCase()] = s;
            }
          }
          _subjects = uniqueMap.values.toList();
          _filteredSubjects = _subjects;
        });
      }
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _meetingDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _meetingDate = picked);
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _meetingTime,
    );
    if (picked != null) {
      setState(() => _meetingTime = picked);
    }
  }

  Future<void> _saveMeeting() async {
    if (!_formKey.currentState!.validate()) return;

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debes estar autenticado para guardar reuniones')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final dt = DateTime(
        _meetingDate.year,
        _meetingDate.month,
        _meetingDate.day,
        _meetingTime.hour,
        _meetingTime.minute,
      );

      final meeting = Meeting(
        id: widget.meeting?.id,
        title: InputSanitizer.sanitizeText(_titleController.text),
        description: InputSanitizer.sanitizeText(_descriptionController.text),
        subject: _selectedSubject.isEmpty ? _titleController.text : _selectedSubject,
        professor: _professorController.text.trim().isEmpty ? 'Profesor' : _professorController.text.trim(),
        meetingDate: dt,
        type: _selectedType,
        isRecurrent: _isRecurrent,
        meetingLink: _linkController.text.trim().isEmpty ? null : _linkController.text.trim(),
        careerId: _selectedCareerId,
        userId: user.id,
      );

      await MeetingService().saveMeeting(meeting);

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar reunión: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.meeting == null ? 'Nueva Reunión' : 'Editar Reunión'),
        actions: [
          if (widget.meeting != null)
            IconButton(
              icon: const Icon(Icons.delete, color: AppColors.error),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Eliminar reunión'),
                    content: const Text('¿Estás seguro de eliminar esta reunión?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Eliminar', style: TextStyle(color: AppColors.error)),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !context.mounted) return;

                try {
                  await MeetingService().deleteMeeting(widget.meeting!.id!);
                  if (context.mounted) Navigator.pop(context, true);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error al eliminar reunión: $e'), backgroundColor: AppColors.error),
                    );
                  }
                }
              },
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Título de la reunión *',
                prefixIcon: Icon(Icons.meeting_room),
              ),
              validator: (v) => Validators.requiredWithMinLength(v, 3, 'El título'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Descripción / Detalles *',
                prefixIcon: Icon(Icons.description),
              ),
              maxLines: 2,
              validator: (v) => Validators.requiredWithMinLength(v, 3, 'La descripción'),
            ),
            const SizedBox(height: 16),
            Autocomplete<Subject>(
              initialValue: TextEditingValue(text: _selectedSubject),
              optionsBuilder: (textVal) {
                return _filteredSubjects.where(
                  (s) => s.name.toLowerCase().contains(textVal.text.toLowerCase()),
                );
              },
              displayStringForOption: (s) => s.name,
              onSelected: (s) {
                setState(() {
                  _selectedSubject = s.name;
                  _professorController.text = s.professor;
                });
              },
              fieldViewBuilder: (ctx, controller, focusNode, onSubmit) {
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Asignatura (opcional)',
                    prefixIcon: Icon(Icons.book),
                  ),
                  onChanged: (v) => _selectedSubject = v,
                );
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _professorController,
              decoration: const InputDecoration(
                labelText: 'Profesor (opcional)',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedType,
              decoration: const InputDecoration(
                labelText: 'Tipo de reunión (opcional)',
                prefixIcon: Icon(Icons.video_camera_front),
              ),
              items: _meetingTypes.map((t) {
                return DropdownMenuItem(value: t, child: Text(t));
              }).toList(),
              onChanged: (v) => setState(() => _selectedType = v!),
            ),
            const SizedBox(height: 16),
            _buildCareerField(),
            TextFormField(
              controller: _linkController,
              decoration: const InputDecoration(
                labelText: 'Link / Enlace de conexión (opcional)',
                hintText: 'https://zoom.us/j/... o https://meet.google.com/...',
                prefixIcon: Icon(Icons.link),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _selectDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Fecha *',
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                      child: Text(DateFormat('dd/MM/yyyy').format(_meetingDate)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: _selectTime,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Hora *',
                        prefixIcon: Icon(Icons.access_time),
                      ),
                      child: Text(_meetingTime.format(context)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Reunión recurrente (Todas las semanas)'),
              subtitle: const Text('Se repetirá semanalmente'),
              value: _isRecurrent,
              activeThumbColor: Theme.of(context).primaryColor,
              onChanged: (v) => setState(() => _isRecurrent = v),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _saveMeeting,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Guardar Reunión'),
            ),
          ],
        ),
      ),
    );
  }
}
