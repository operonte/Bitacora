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

  /// Carrera a la que pertenece la reunión. Antes se tomaba en silencio de la
  /// carrera activa al guardar y no había forma de corregirla; ahora se elige
  /// acá, es lo primero del formulario, y de ella dependen las asignaturas que
  /// se ofrecen más abajo.
  String? _selectedCareerId;

  /// Privada = solo la ve quien la creó. Compartida = la ven los miembros de
  /// [_selectedCareerId]. Arranca privada a propósito: publicar al grupo es
  /// una decisión consciente, no el default.
  bool _isPrivate = true;

  bool _isRecurrent = false;
  DateTime _meetingDate = DateTime.now().add(const Duration(hours: 2));
  TimeOfDay _meetingTime = const TimeOfDay(hour: 14, minute: 0);

  bool _isLoading = false;
  List<Subject> _subjects = [];

  /// Materias que creó el usuario. No están atadas a ninguna carrera —el
  /// modelo Subject no guarda carrera— así que se ofrecen en todas.
  List<Subject> _ownSubjects = [];

  /// Fuerza a reconstruir el desplegable al cambiar de carrera: su
  /// `initialValue` solo se lee cuando se construye, así que sin una key nueva
  /// el campo seguiría mostrando una asignatura que ya no está en la lista.
  Key _subjectFieldKey = UniqueKey();

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
    // _initData primero: fija la carrera, y de ella depende qué asignaturas
    // carga _loadSubjects.
    _initData();
    _loadSubjects();
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
      // Si se perdió la carrera, compartirla dejaría de tener sentido.
      _isPrivate = m.isPrivate || _selectedCareerId == null;
    } else {
      _selectedCareerId = CareerService().getSelectedCareer()?.id;
    }

    // Ya no existe "sin carrera": no se puede usar la app sin pertenecer a
    // alguna. Si la guardada se perdió (el usuario salió de esa carrera), se
    // propone la activa para que la reunión quede clasificada al guardarla.
    if (!CareerService().careerIds.contains(_selectedCareerId)) {
      final careers = CareerService().getCareers();
      _selectedCareerId = CareerService().getSelectedCareer()?.id ??
          (careers.isNotEmpty ? careers.first.id : null);
    }
  }

  Widget _buildCareerField() {
    // Sin las desactivadas, salvo que sea la ya elegida — para no reasignar
    // en silencio una reunión existente a otra carrera al abrir el
    // formulario. El servidor igual rechaza guardar en una carrera inactiva.
    final careers = CareerService()
        .getCareers()
        .where((c) => c.isActive || c.id == _selectedCareerId)
        .toList();
    if (careers.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        initialValue: careers.any((c) => c.id == _selectedCareerId)
            ? _selectedCareerId
            : null,
        decoration: const InputDecoration(
          labelText: 'Carrera',
          prefixIcon: Icon(Icons.school_outlined),
          border: OutlineInputBorder(),
          helperText: 'Define qué asignaturas puedes elegir',
        ),
        items: [
          for (final c in careers)
            DropdownMenuItem<String>(
              value: c.id,
              child: Text(c.isActive ? c.name : '${c.name} (inactiva)'),
            ),
        ],
        validator: (value) => value == null ? 'Elige una carrera' : null,
        onChanged: (value) => setState(() {
          _selectedCareerId = value;
          // Cambiar de carrera cambia la lista de asignaturas: si la que
          // estaba elegida era de la carrera anterior, se descarta.
          _rebuildSubjects();
          // Autocomplete no vuelve a llamar a optionsBuilder solo porque
          // _subjects cambió: con el campo de asignatura vacío se quedaba
          // mostrando las opciones de la carrera anterior. La key nueva
          // fuerza a remontarlo con la lista ya actualizada.
          _subjectFieldKey = UniqueKey();
        }),
      ),
    );
  }

  /// Elección de visibilidad. Solo tiene sentido con una carrera elegida:
  /// sin carrera no hay grupo destinatario, así que se oculta.
  Widget _buildVisibilityField() {
    if (_selectedCareerId == null) return const SizedBox.shrink();

    final careerName = CareerService()
        .getCareers()
        .where((c) => c.id == _selectedCareerId)
        .map((c) => c.name)
        .firstOrNull;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        margin: EdgeInsets.zero,
        child: SwitchListTile(
          value: !_isPrivate,
          onChanged: (v) => setState(() => _isPrivate = !v),
          secondary: Icon(_isPrivate ? Icons.lock_outline : Icons.groups_outlined),
          title: Text(_isPrivate ? 'Reunión privada' : 'Reunión compartida'),
          subtitle: Text(
            _isPrivate
                ? 'Solo tú la ves'
                : 'La ven los miembros de ${careerName ?? 'la carrera'}',
          ),
        ),
      ),
    );
  }

  /// Carga las materias: primero las predefinidas de la carrera elegida (que
  /// están en memoria y aparecen al instante) y después las propias del
  /// usuario, que hay que ir a buscar a la red.
  Future<void> _loadSubjects() async {
    setState(_rebuildSubjects);

    try {
      final dbSubjects = await SupabaseDbService().getSubjects();
      if (!mounted) return;
      setState(() {
        _ownSubjects = dbSubjects;
        _rebuildSubjects();
      });
    } catch (_) {
      // Sin red quedan solo las predefinidas, que ya están puestas.
    }
  }

  /// Rearma la lista de asignaturas para [_selectedCareerId].
  ///
  /// Es la cascada: la carrera acota qué asignaturas se ofrecen, para que no
  /// se pueda agendar una reunión de una materia de Informática dentro de
  /// Teología. Las materias propias van siempre, porque no pertenecen a
  /// ninguna carrera en particular.
  void _rebuildSubjects() {
    final user = Supabase.instance.client.auth.currentUser;
    final uId = user?.id ?? '';
    final uName = user?.email ?? 'Usuario';

    final predefined = <Subject>[];
    var counter = 0;
    for (final career in CareerService().getCareers()) {
      if (_selectedCareerId != null && career.id != _selectedCareerId) continue;
      for (final s in career.predefinedSubjects) {
        // Inactiva (semestre anterior) y no es la ya elegida: no se ofrece.
        // Sigue disponible igual en Archivos/Material docente.
        if (!s.isActive && s.name.toLowerCase() != _selectedSubject.toLowerCase()) {
          continue;
        }
        predefined.add(Subject(
          id: 'pred_${counter++}',
          name: s.name,
          professor: s.professor,
          userId: uId,
          userName: uName,
          createdAt: DateTime.now(),
          isActive: s.isActive,
        ));
      }
    }

    final unicas = <String, Subject>{};
    for (final s in [...predefined, ..._ownSubjects]) {
      unicas.putIfAbsent(s.name.toLowerCase(), () => s);
    }
    _subjects = unicas.values.toList();

    if (_selectedSubject.isEmpty) return;

    final actual = _selectedSubject.toLowerCase();
    if (_subjects.any((s) => s.name.toLowerCase() == actual)) return;

    // La asignatura elegida no existe en la carrera nueva. Antes se conservaba
    // si parecía texto libre; ahora el campo solo admite materias de la
    // carrera, así que se descarta y hay que elegir de nuevo.
    _selectedSubject = '';
    _professorController.clear();
    _subjectFieldKey = UniqueKey();
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
        subject: _selectedSubject,
        professor: _professorController.text.trim().isEmpty ? 'Profesor' : _professorController.text.trim(),
        meetingDate: dt,
        type: _selectedType,
        isRecurrent: _isRecurrent,
        meetingLink: _linkController.text.trim().isEmpty ? null : _linkController.text.trim(),
        careerId: _selectedCareerId,
        userId: user.id,
        // Sin carrera no hay grupo destinatario: la restricción
        // meetings_shared_needs_career_chk lo rechazaría en la base.
        isPrivate: _selectedCareerId == null ? true : _isPrivate,
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
            // Desplegable y obligatoria, no texto libre.
            //
            // Antes era un Autocomplete que aceptaba cualquier cosa y, si se
            // dejaba vacío, guardaba el título de la reunión como asignatura.
            // Eso metía en la lista de materias de la carrera cadenas que no
            // eran materias de nada, y desde el endurecimiento 16 el servidor
            // lo rechaza.
            DropdownButtonFormField<String>(
              key: _subjectFieldKey,
              initialValue: _subjects.any((s) => s.name == _selectedSubject)
                  ? _selectedSubject
                  : null,
              decoration: InputDecoration(
                labelText: 'Asignatura *',
                prefixIcon: const Icon(Icons.book),
                helperText: _subjects.isEmpty
                    ? 'Esta carrera no tiene materias cargadas'
                    : null,
              ),
              items: _subjects
                  .map((s) => DropdownMenuItem<String>(
                        value: s.name,
                        child: Text(s.name, overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Elige una asignatura' : null,
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _selectedSubject = value;
                  // El profesor de la materia, si lo tiene: ahorra escribirlo
                  // y evita que cada reunión lo escriba distinto.
                  final materia =
                      _subjects.firstWhere((s) => s.name == value);
                  if (materia.professor.isNotEmpty) {
                    _professorController.text = materia.professor;
                  }
                });
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
            _buildVisibilityField(),
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
