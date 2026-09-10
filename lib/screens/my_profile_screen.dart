import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth_service.dart';
import '../colors.dart';
import '../models/career_model.dart';
import '../services/career_service.dart';
import '../services/profile_service.dart';
import '../services/story_service.dart';
import '../utils/custom_file_picker.dart';
import '../utils/file_security_validator.dart';
import '../utils/input_sanitizer.dart';
import 'announcements_screen.dart';
import 'assign_task_screen.dart';
import 'attendance_screen.dart';
import 'career_attendance_screen.dart';
import 'career_grades_screen.dart';
import 'career_members_directory_screen.dart';
import 'cover_photo_positioner_screen.dart';
import 'my_attendance_screen.dart';
import 'my_grades_screen.dart';
import 'public_profile_screen.dart';
import 'story_viewer_screen.dart';
import 'student_uploads_screen.dart';
import 'teacher_panel_screen.dart';
import 'teacher_subjects_screen.dart';

/// Mi perfil: lo que antes era un diálogo con nombre y una URL de foto
/// pegada a mano, ahora una pantalla propia con foto subida de verdad, bio
/// y datos personales opcionales. Cada campo lo llena quien es dueño del
/// perfil — nada se completa solo.
class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

/// A qué foto va lo que se elija con el selector de archivos: la principal
/// (avatar), la de portada (atrás del avatar, como Facebook) o una más de
/// la tira de fotos extra.
enum _PhotoTarget { main, cover, extra }

class _MyProfileScreenState extends State<MyProfileScreen> {
  final _service = ProfileService();
  final _careerService = CareerService();
  final _authService = AuthService();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _ageController = TextEditingController();
  /// Lista cerrada, no texto libre — pero si el perfil ya tenía algo
  /// escrito a mano de antes que no calce con las opciones, se agrega para
  /// no perderlo en silencio al abrir el desplegable.
  static const _generoOpciones = ['Masculino', 'Femenino'];
  String? _gender;

  static const _situacionSentimentalOpciones = [
    'Soltero/a',
    'En una relación',
    'Comprometido/a',
    'Casado/a',
    'En convivencia',
    'Es complicado',
    'Separado/a',
    'Viudo/a',
  ];
  String? _relationshipStatus;
  final _religionController = TextEditingController();
  final _phoneController = TextEditingController();
  final _socialMediaController = TextEditingController();
  final _interestsController = TextEditingController();
  final _previousCareerController = TextEditingController();
  final _occupationController = TextEditingController();

  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;
  double _uploadProgress = 0;
  String? _error;

  /// Mi historia activa (dura 48 h), o null si no tengo ninguna vigente.
  Map<String, dynamic>? _myStory;
  bool _uploadingStory = false;
  double _storyProgress = 0;

  // Información académica: carrera activa, todas las carreras a las que
  // pertenece y sus herramientas — vive acá y no en Configuración porque es
  // "quién sos", no "cómo se ve la app".
  Career? _selectedCareer;
  List<Career> _careers = [];

  @override
  void initState() {
    super.initState();
    _load();
    _loadCareerData();
    _loadMyStory();
  }

  Future<void> _loadMyStory() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final story = await StoryService.getActiveStory(uid);
      if (mounted) setState(() => _myStory = story);
    } catch (_) {
      // Sin bloquear el perfil si falla: se ve igual, solo sin el anillo.
    }
  }

  Future<void> _loadCareerData() async {
    // Sincronizar automáticamente materias y profesores desde Supabase —
    // vivía en Configuración, se mueve acá con el resto de lo académico.
    try {
      await _careerService.reloadCareerWithUpdatedSubjects();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _selectedCareer = _careerService.getSelectedCareer();
      _careers = _careerService.getCareers();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _ageController.dispose();
    _religionController.dispose();
    _phoneController.dispose();
    _socialMediaController.dispose();
    _interestsController.dispose();
    _previousCareerController.dispose();
    _occupationController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await _service.getMyProfile();
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _nameController.text = (profile?['display_name'] as String?) ?? '';
        _bioController.text = (profile?['bio'] as String?) ?? '';
        _ageController.text = profile?['age']?.toString() ?? '';
        final generoGuardado = (profile?['gender'] as String?)?.trim();
        _gender = (generoGuardado == null || generoGuardado.isEmpty)
            ? null
            : generoGuardado;
        final situacionGuardada = (profile?['relationship_status'] as String?)
            ?.trim();
        _relationshipStatus =
            (situacionGuardada == null || situacionGuardada.isEmpty)
            ? null
            : situacionGuardada;
        _religionController.text = (profile?['religion'] as String?) ?? '';
        _phoneController.text = (profile?['phone'] as String?) ?? '';
        _socialMediaController.text =
            (profile?['social_media'] as String?) ?? '';
        _interestsController.text = (profile?['interests'] as String?) ?? '';
        _previousCareerController.text =
            (profile?['previous_career'] as String?) ?? '';
        _occupationController.text =
            (profile?['occupation'] as String?) ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final name = InputSanitizer.sanitizeText(_nameController.text);
      if (name.isNotEmpty) {
        await Supabase.instance.client.auth.updateUser(
          UserAttributes(data: {'full_name': name}),
        );
      }
      final ageText = _ageController.text.trim();
      await _service.updateMyProfile(
        bio: InputSanitizer.sanitizeText(_bioController.text),
        age: ageText.isEmpty ? null : int.tryParse(ageText),
        gender: _gender ?? '',
        relationshipStatus: _relationshipStatus ?? '',
        religion: InputSanitizer.sanitizeText(_religionController.text),
        phone: InputSanitizer.sanitizeText(_phoneController.text),
        socialMedia: InputSanitizer.sanitizeText(_socialMediaController.text),
        interests: InputSanitizer.sanitizeText(_interestsController.text),
        previousCareer: InputSanitizer.sanitizeText(
          _previousCareerController.text,
        ),
        occupation: InputSanitizer.sanitizeText(_occupationController.text),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Perfil actualizado'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAndUpload({required _PhotoTarget target}) async {
    try {
      final file = await CustomFilePicker.pickFile();
      if (file == null) return;
      if (file.head.isEmpty) return;

      final validation = FileSecurityValidator.validateFile(
        fileName: file.name,
        sizeInBytes: file.size,
        bytes: file.head,
      );
      if (!validation.isValid || validation.fileCategory != 'Imagen') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                validation.isValid
                    ? 'Elige una imagen (jpg, png, webp).'
                    : (validation.errorMessage ?? 'Archivo no permitido.'),
              ),
            ),
          );
        }
        return;
      }

      setState(() {
        _uploadingPhoto = true;
        _uploadProgress = 0;
      });

      final url = await _service.uploadPhoto(
        fileName: file.name,
        sizeBytes: file.size,
        extension: file.extension,
        filePath: file.path,
        bytes: file.bytes,
        onProgress: (p) {
          if (mounted) setState(() => _uploadProgress = p);
        },
      );

      switch (target) {
        case _PhotoTarget.main:
          await _service.setMainPhoto(url);
        case _PhotoTarget.cover:
          await _service.setCoverPhoto(url);
        case _PhotoTarget.extra:
          await _service.addExtraPhoto(url);
      }
      await _load();
      // Antes de "fijarla": recién subida es cuando tiene sentido dejarla
      // acomodada, no como un paso aparte que hay que acordarse de volver
      // a hacer después.
      if (target == _PhotoTarget.cover && mounted) {
        await _openCoverPositioner(url);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  /// Con portada ya puesta, tocarla ofrece elegir entre acomodarla o
  /// cambiarla — sin esto, cada toque volvía a abrir el selector de
  /// archivos y perdía de vista la opción de solo reacomodar.
  Future<void> _onCoverTap(String? coverUrl) async {
    if (coverUrl == null || coverUrl.isEmpty) {
      await _pickAndUpload(target: _PhotoTarget.cover);
      return;
    }
    final accion = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.open_with),
              title: const Text('Acomodar'),
              onTap: () => Navigator.pop(ctx, 'acomodar'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Cambiar foto'),
              onTap: () => Navigator.pop(ctx, 'cambiar'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || accion == null) return;
    if (accion == 'acomodar') {
      await _openCoverPositioner(coverUrl);
    } else if (accion == 'cambiar') {
      await _pickAndUpload(target: _PhotoTarget.cover);
    }
  }

  Future<void> _openCoverPositioner(String url) async {
    final actual =
        (_profile?['cover_photo_offset'] as num?)?.toDouble() ?? 0.0;
    final nuevo = await Navigator.push<double>(
      context,
      MaterialPageRoute(
        builder: (_) => CoverPhotoPositionerScreen(
          imageUrl: url,
          initialOffset: actual,
        ),
      ),
    );
    if (nuevo == null || !mounted) return;
    try {
      await _service.setCoverPhotoOffset(nuevo);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyError(e))));
      }
    }
  }

  Future<void> _removeExtraPhoto(String url) async {
    try {
      await _service.removeExtraPhoto(url);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyError(e))));
      }
    }
  }

  /// El RPC de subir/borrar fotos extra devuelve un PostgrestException, no
  /// una Exception simple — `.toString()` de esa no da un texto limpio para
  /// mostrar (sale "PostgrestException(message: ..., code: ...)" entero).
  String _friendlyError(Object e) => e is PostgrestException
      ? e.message
      : e.toString().replaceAll('Exception: ', '');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi perfil'),
        actions: [
          if (!_loading)
            IconButton(
              icon: const Icon(Icons.visibility_outlined),
              tooltip: 'Ver como lo ve tu carrera',
              onPressed: () {
                final uid = Supabase.instance.client.auth.currentUser?.id;
                if (uid == null) return;
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PublicProfileScreen(
                      userId: uid,
                      fallbackName: _nameController.text,
                    ),
                  ),
                );
              },
            ),
          if (!_loading)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Guardar',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 40),
              children: [
                _banner(),
                const SizedBox(height: 56),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    children: [
                      _card(
                        title: 'Sobre mí',
                        children: [
                          TextField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Nombre',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          if ((_profile?['email'] as String?)
                                  ?.isNotEmpty ??
                              false) ...[
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Icon(
                                  Icons.email_outlined,
                                  size: 18,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _profile!['email'] as String,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 12),
                          TextField(
                            controller: _bioController,
                            maxLines: 3,
                            maxLength: 300,
                            decoration: const InputDecoration(
                              labelText: 'Bio (opcional)',
                              hintText: 'Cuéntanos algo sobre ti',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _card(
                        title: 'Fotos',
                        subtitle:
                            'Hasta ${ProfileService.maxExtraPhotos} fotos además de tu foto principal.',
                        children: [_extraPhotosStrip()],
                      ),
                      const SizedBox(height: 16),
                      _card(
                        title: 'Información personal',
                        subtitle:
                            'Todo opcional, y visible para el resto de tu carrera.',
                        children: [
                          TextField(
                            controller: _ageController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Edad (opcional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String?>(
                            initialValue: _gender,
                            decoration: const InputDecoration(
                              labelText: 'Género (opcional)',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Sin especificar'),
                              ),
                              for (final opcion in {
                                ..._generoOpciones,
                                if (_gender != null) _gender!,
                              })
                                DropdownMenuItem<String?>(
                                  value: opcion,
                                  child: Text(opcion),
                                ),
                            ],
                            onChanged: (v) => setState(() => _gender = v),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String?>(
                            initialValue: _relationshipStatus,
                            decoration: const InputDecoration(
                              labelText: 'Situación sentimental (opcional)',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Sin especificar'),
                              ),
                              for (final opcion in {
                                ..._situacionSentimentalOpciones,
                                if (_relationshipStatus != null)
                                  _relationshipStatus!,
                              })
                                DropdownMenuItem<String?>(
                                  value: opcion,
                                  child: Text(opcion),
                                ),
                            ],
                            onChanged: (v) =>
                                setState(() => _relationshipStatus = v),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _religionController,
                            decoration: const InputDecoration(
                              labelText: 'Creencias / religión (opcional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Teléfono / contacto (opcional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _socialMediaController,
                            decoration: const InputDecoration(
                              labelText: 'Redes sociales (opcional)',
                              hintText: 'Ej: @usuario en Instagram',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _interestsController,
                            decoration: const InputDecoration(
                              labelText: 'Intereses / hobbies (opcional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _previousCareerController,
                            decoration: const InputDecoration(
                              labelText: 'Estudios (opcional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _occupationController,
                            decoration: const InputDecoration(
                              labelText: 'Trabajo o profesión (opcional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      ..._academicSections(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  /// Todo lo académico: carrera activa, avisos, progreso, herramientas de
  /// docente y la cuenta en sí. Antes vivía repartido en Configuración —
  /// junto al perfil es donde tiene sentido, es "quién sos", no "cómo se ve
  /// la app".
  List<Widget> _academicSections() {
    final career = _selectedCareer;
    final isDocenteActiva = career != null && _careerService.isDocente(career.id);
    return [
      if (career != null) ...[
        _sectionHeader('Comunicación', Icons.campaign_outlined),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.campaign_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Anuncios'),
                subtitle: Text('Avisos de ${career.name}'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AnnouncementsScreen(career: career),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.groups_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Miembros'),
                subtitle: Text('Directorio de ${career.name}'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        CareerMembersDirectoryScreen(career: career),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],

      // "Mi progreso" es del alumno: notas y asistencia propias. Un docente
      // no tiene nada que entregar en esta carrera, así que no le aparece —
      // lo suyo vive en "Herramientas de docente" más abajo.
      if (career != null && !_careerService.isDocente(career.id)) ...[
        _sectionHeader('Mi progreso', Icons.school_outlined),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.grade_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Mis notas'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MyGradesScreen(career: career),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.checklist_rtl,
                  color: AppColors.primary,
                ),
                title: const Text('Mi asistencia'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MyAttendanceScreen(career: career),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],

      if (career != null && _careerService.isDocente(career.id)) ...[
        _sectionHeader('Herramientas de docente', Icons.school),
        const SizedBox(height: 8),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.add_task,
                  color: AppColors.primary,
                ),
                title: const Text('Asignar tarea'),
                subtitle: const Text('Crea una tarea oficial para tus alumnos'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AssignTaskScreen(career: career),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.upload_file_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Archivos de alumnos'),
                subtitle: const Text(
                  'Lo que suban tus alumnos en tus asignaturas',
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StudentUploadsScreen(career: career),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.checklist_rtl,
                  color: AppColors.primary,
                ),
                title: const Text('Asistencia'),
                subtitle: Text('Marcar asistencia de ${career.name}'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AttendanceScreen(career: career),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.table_chart_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Resumen de asistencia'),
                subtitle: const Text(
                  'Todos los alumnos y su % en cada asignatura',
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CareerAttendanceScreen(career: career),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.grading_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Notas de la carrera'),
                subtitle: const Text(
                  'Todos los alumnos y sus notas en cada asignatura',
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CareerGradesScreen(career: career),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.warning,
                ),
                title: const Text('Panel de riesgo'),
                subtitle: const Text('Quién se está quedando atrás'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TeacherPanelScreen(career: career),
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.menu_book_outlined,
                  color: AppColors.primary,
                ),
                title: const Text('Mis asignaturas'),
                subtitle: const Text(
                  'Qué materias impartes, para cruzar con el semestre del alumno',
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TeacherSubjectsScreen(career: career),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],

      // El semestre acota qué materias y avisos ve un alumno; un docente no
      // tiene uno propio en esta carrera.
      if (career != null && !_careerService.isDocente(career.id)) ...[
        _sectionHeader('Mi semestre', Icons.calendar_view_month_outlined),
        const SizedBox(height: 8),
        _buildSemesterPicker(career),
        const SizedBox(height: 24),
      ],

      // El título y "Unirse a otra carrera" son de alumno (autoinscribirse
      // te suma como estudiante, ver _joinCareerDialog/admin_add_member) —
      // un docente no se une solo, lo agrega el súper usuario. La lista en
      // sí queda igual: sigue siendo el único lugar para cambiar de carrera
      // activa, y un docente puede dar clases en más de una.
      _sectionHeader(
        isDocenteActiva ? 'Tus carreras' : 'Estudias dos o más carreras',
        Icons.school_outlined,
      ),
      const SizedBox(height: 8),
      Card(
        child: Column(
          children: [
            ..._careers.map(_careerTile),
            if (!isDocenteActiva) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(
                  Icons.add_circle_outline,
                  color: AppColors.primary,
                ),
                title: const Text('Unirse a otra carrera'),
                subtitle: const Text('Ingresar una clave de acceso'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: _joinCareerDialog,
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 24),

      _sectionHeader('Cuenta', Icons.manage_accounts_outlined),
      const SizedBox(height: 8),
      Card(
        child: Column(
          children: [
            // "Salir de la carrera" es para quien se autoinscribió como
            // alumno; a un docente lo agregó el súper usuario, así que acá
            // solo le corresponde cerrar sesión.
            if (!isDocenteActiva) ...[
              ListTile(
                leading: const Icon(
                  Icons.school_outlined,
                  color: AppColors.warning,
                ),
                title: const Text('Salir de todas las carreras'),
                subtitle: const Text('Volver a la selección de carrera'),
                onTap: _logout,
              ),
              const Divider(height: 1),
            ],
            ListTile(
              leading: const Icon(Icons.exit_to_app, color: AppColors.error),
              title: const Text('Cerrar sesión de la cuenta'),
              subtitle: const Text('Cerrar Sesión'),
              onTap: _signOutAccount,
            ),
          ],
        ),
      ),
    ];
  }

  Widget _sectionHeader(String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  /// Semestres cargados en el catálogo de [career] — los mismos valores que
  /// ya etiquetan cada materia, para no inventar una lista aparte. Se
  /// ordenan por el número de trimestre (1, 2, 3…), no alfabéticamente: como
  /// texto, "10mo" queda antes que "2do".
  List<String> _semestresDe(Career career) {
    final valores =
        career.predefinedSubjects
            .map((s) => s.semester?.trim() ?? '')
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList();
    valores.sort((a, b) {
      final na = _trimestreNumero(a);
      final nb = _trimestreNumero(b);
      if (na != null && nb != null) return na.compareTo(nb);
      if (na != null) return -1;
      if (nb != null) return 1;
      return a.compareTo(b);
    });
    return valores;
  }

  /// El valor guardado trae "<Año> · <N>º Trimestre" (viene tal cual de la
  /// malla cargada); acá solo se muestra la parte del trimestre — el año ya
  /// está implícito en cuál es, y repetirlo en cada ítem del desplegable
  /// solo hacía más largo el texto sin sumar información.
  String _trimestreLabel(String semester) {
    final idx = semester.indexOf('·');
    return idx == -1 ? semester : semester.substring(idx + 1).trim();
  }

  /// No todas las mallas etiquetan el semestre igual: unas carreras usan
  /// ordinal arábigo ("1er Trimestre"), otras número romano ("Sem. VII") —
  /// es texto libre, cargado a mano por carrera. Se prueban las dos formas.
  int? _trimestreNumero(String semester) {
    final label = _trimestreLabel(semester);
    final arabigo = RegExp(r'(\d+)').firstMatch(label);
    if (arabigo != null) return int.tryParse(arabigo.group(1)!);
    final romano = RegExp(
      r'\b([IVXLCDM]+)\b',
      caseSensitive: false,
    ).firstMatch(label);
    return romano == null ? null : _romanoANumero(romano.group(1)!);
  }

  int? _romanoANumero(String romano) {
    const valores = {
      'I': 1,
      'V': 5,
      'X': 10,
      'L': 50,
      'C': 100,
      'D': 500,
      'M': 1000,
    };
    final letras = romano.toUpperCase().split('');
    var total = 0;
    var anterior = 0;
    for (final letra in letras.reversed) {
      final valor = valores[letra];
      if (valor == null) return null;
      total += valor < anterior ? -valor : valor;
      anterior = valor;
    }
    return total == 0 ? null : total;
  }

  Widget _buildSemesterPicker(Career career) {
    final opciones = _semestresDe(career);
    if (opciones.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            '${career.name} todavía no tiene sus materias organizadas por semestre.',
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      );
    }
    final actual = _careerService.semesterFor(career.id);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: DropdownButtonFormField<String?>(
          initialValue: opciones.contains(actual) ? actual : null,
          decoration: const InputDecoration(
            labelText: '¿En qué semestre estás?',
            border: InputBorder.none,
          ),
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('Sin elegir'),
            ),
            ...opciones.map(
              (s) => DropdownMenuItem<String?>(
                value: s,
                child: Text(_trimestreLabel(s)),
              ),
            ),
          ],
          onChanged: (value) async {
            if (value == null) return;
            try {
              await _careerService.setMySemester(career.id, value);
              if (mounted) {
                setState(() {});
                _showSnack('Semestre guardado', Colors.green);
              }
            } catch (e) {
              _showSnack('No se pudo guardar: $e', AppColors.error);
            }
          },
        ),
      ),
    );
  }

  Widget _careerTile(Career career) {
    final isActive = _selectedCareer?.id == career.id;
    final logoUrl = career.logoUrl;
    return ListTile(
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (logoUrl != null && logoUrl.isNotEmpty) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
              backgroundImage: NetworkImage(logoUrl),
            ),
            const SizedBox(width: 8),
          ],
          Icon(
            isActive ? Icons.radio_button_checked : Icons.radio_button_off,
            color: isActive ? AppColors.primary : AppColors.textSecondary,
          ),
        ],
      ),
      title: Text(
        career.name,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(isActive ? 'Carrera activa' : 'Tocar para activar'),
      // A un docente lo agregó el súper usuario, no se autoinscribió —
      // salir por su cuenta no le corresponde.
      trailing: (_careers.length > 1 && !_careerService.isDocente(career.id))
          ? IconButton(
              icon: const Icon(Icons.logout, color: AppColors.error, size: 20),
              tooltip: 'Salir de esta carrera',
              onPressed: () => _leaveCareer(career),
            )
          : null,
      onTap: isActive ? null : () => _setActiveCareer(career),
    );
  }

  Future<void> _setActiveCareer(Career career) async {
    await _careerService.setActiveCareer(career.id);
    _loadCareerData();
  }

  Future<void> _joinCareerDialog() async {
    // Refrescar las carreras creadas en el admin para poder validar su clave.
    await _careerService.loadRemoteCareers();

    final controller = TextEditingController();
    String? errorText;

    if (!mounted) return;
    final added = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Unirse a otra carrera'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ingresa la clave de acceso de la carrera o grupo al que quieres unirte.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Clave de acceso',
                  border: const OutlineInputBorder(),
                  errorText: errorText,
                ),
                onSubmitted: (_) {},
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () async {
                final key = controller.text.trim();
                Career? career;
                try {
                  // Consulta al servidor: la clave ya no viaja en la app.
                  career = await _careerService.validateAccessKey(key);
                } catch (e) {
                  // join_career() bloquea 15 min tras 5 intentos fallidos y
                  // avisa con esta excepción puntual; el resto de errores del
                  // servidor se tratan como falta de conexión.
                  final message = e is PostgrestException ? e.message : '';
                  setLocal(
                    () => errorText = message.contains('Demasiados intentos')
                        ? message
                        : 'Sin conexión para validar la clave',
                  );
                  return;
                }
                if (career == null) {
                  setLocal(() => errorText = 'Clave de acceso inválida');
                  return;
                }
                if (_careerService.isMember(career.id)) {
                  setLocal(() => errorText = 'Ya perteneces a esta carrera');
                  return;
                }
                await _careerService.addCareer(career);
                if (ctx.mounted) Navigator.pop(ctx, true);
              },
              child: const Text('Unirse'),
            ),
          ],
        ),
      ),
    );

    if (added == true) {
      _loadCareerData();
      _showSnack('✅ Te uniste a la carrera', Colors.green);
    }
  }

  Future<void> _leaveCareer(Career career) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salir de la carrera'),
        content: Text(
          '¿Seguro que quieres salir de "${career.name}"? Dejarás de ver sus tareas. '
          'Podrás volver a unirte con la clave de acceso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await _careerService.removeCareer(career.id);

    // Si era la última carrera, volver para que el routing muestre el acceso.
    if (_careerService.getCareers().isEmpty && mounted) {
      Navigator.of(context).pop();
      return;
    }
    _loadCareerData();
    _showSnack('Saliste de ${career.name}', Colors.orange);
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salir de la carrera'),
        content: const Text(
          '¿Seguro que quieres salir? Tendrás que ingresar la clave de acceso nuevamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Salir', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _careerService.clearSelectedCareer();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _signOutAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text(
          '¿Seguro que quieres cerrar sesión de tu cuenta? Se borrará la caché local y deberás iniciar sesión nuevamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Cerrar sesión',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _authService.signOut();
    await _careerService.clearSelectedCareer();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Widget _banner() {
    final photoUrl = _profile?['photo_url'] as String?;
    final coverUrl = _profile?['cover_photo_url'] as String?;
    final coverOffset = (_profile?['cover_photo_offset'] as num?)
            ?.toDouble() ??
        0.0;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        GestureDetector(
          onTap: _uploadingPhoto ? null : () => _onCoverTap(coverUrl),
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              gradient: (coverUrl == null || coverUrl.isEmpty)
                  ? const LinearGradient(
                      colors: [AppColors.primary, AppColors.primaryLight],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              image: (coverUrl != null && coverUrl.isNotEmpty)
                  ? DecorationImage(
                      image: NetworkImage(coverUrl),
                      fit: BoxFit.cover,
                      alignment: Alignment(0, coverOffset),
                    )
                  : null,
            ),
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(top: 76, child: _avatarPicker(photoUrl)),
      ],
    );
  }

  Widget _avatarPicker(String? photoUrl) {
    final tieneHistoria = _myStory != null;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GestureDetector(
          onTap: _uploadingPhoto
              ? null
              : () => _pickAndUpload(target: _PhotoTarget.main),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              shape: BoxShape.circle,
              border: tieneHistoria
                  ? Border.all(color: AppColors.accentTeal, width: 3)
                  : null,
            ),
            child: CircleAvatar(
              radius: 48,
              backgroundColor: AppColors.primary.withValues(alpha: 0.15),
              backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                  ? NetworkImage(photoUrl)
                  : null,
              child: (photoUrl == null || photoUrl.isEmpty)
                  ? const Icon(Icons.person, size: 44, color: AppColors.primary)
                  : null,
            ),
          ),
        ),
        if (_uploadingPhoto)
          Positioned.fill(
            child: IgnorePointer(
              child: CircleAvatar(
                backgroundColor: Colors.black.withValues(alpha: 0.4),
                child: Text(
                  '${(_uploadProgress * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          )
        else
          Positioned(
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt,
                  size: 16,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        // Insignia de historia, esquina opuesta a la de cambiar la foto —
        // con su propio InkWell, para no competir con el tap de arriba.
        Positioned(
          left: -2,
          top: -2,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _uploadingStory ? null : _onStoryBadgeTap,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF7A00), Color(0xFFE1306C)],
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
                child: _uploadingStory
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                          value: _storyProgress > 0 ? _storyProgress : null,
                        ),
                      )
                    : Icon(
                        tieneHistoria
                            ? Icons.visibility_outlined
                            : Icons.add,
                        size: 16,
                        color: Colors.white,
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Sin historia, sube una directo. Con una activa, deja elegir entre
  /// verla o reemplazarla — tocar la insignia no debería borrarla por
  /// accidente.
  Future<void> _onStoryBadgeTap() async {
    final historia = _myStory;
    if (historia == null) {
      await _pickAndUploadStory();
      return;
    }
    final accion = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('Ver mi historia'),
              onTap: () => Navigator.pop(ctx, 'ver'),
            ),
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Reemplazar historia'),
              onTap: () => Navigator.pop(ctx, 'reemplazar'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || accion == null) return;
    if (accion == 'ver') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => StoryViewerScreen(
            mediaUrl: historia['media_url'] as String,
            mediaType: historia['media_type'] as String,
            ownerName: 'Mi historia',
            isOwn: true,
            onDelete: () async {
              await StoryService.deleteMyStory();
              await _loadMyStory();
            },
          ),
        ),
      );
    } else if (accion == 'reemplazar') {
      await _pickAndUploadStory();
    }
  }

  Future<void> _pickAndUploadStory() async {
    try {
      final file = await CustomFilePicker.pickFile();
      if (file == null || file.head.isEmpty) return;

      final validation = FileSecurityValidator.validateFile(
        fileName: file.name,
        sizeInBytes: file.size,
        bytes: file.head,
      );
      final categoria = validation.fileCategory;
      if (!validation.isValid ||
          (categoria != 'Imagen' && categoria != 'Video')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                validation.isValid
                    ? 'Elige una foto o un video.'
                    : (validation.errorMessage ?? 'Archivo no permitido.'),
              ),
            ),
          );
        }
        return;
      }

      final esVideo = categoria == 'Video';
      // No hay forma de medir la duración real sin sumar un paquete nuevo
      // de video a la app (se evaluó video_trimmer/ffmpeg_kit_flutter y no
      // se pudo: ver StoryService) — este tope de tamaño es solo una
      // referencia razonable para "unos 30 segundos", no una medición
      // exacta. 20MB quedaba corto para un video real de teléfono: 29
      // segundos en 1080p ronda los 30-60MB según la calidad.
      const videoSizeCapMb = 80;
      if (esVideo && file.size > videoSizeCapMb * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Ese video es muy pesado para una historia de unos 30 '
                'segundos (máximo ${videoSizeCapMb}MB).',
              ),
            ),
          );
        }
        return;
      }

      setState(() {
        _uploadingStory = true;
        _storyProgress = 0;
      });

      await StoryService.uploadStory(
        fileName: file.name,
        sizeBytes: file.size,
        mimeType: file.extension.isNotEmpty
            ? file.extension
            : 'application/octet-stream',
        mediaType: esVideo ? 'video' : 'photo',
        filePath: file.path,
        bytes: file.bytes,
        onProgress: (p) {
          if (mounted) setState(() => _storyProgress = p);
        },
      );
      await _loadMyStory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Historia publicada — se borra sola en 48 horas'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _uploadingStory = false);
    }
  }

  Widget _extraPhotosStrip() {
    final photos = List<String>.from(
      (_profile?['extra_photo_urls'] as List?) ?? [],
    );
    return SizedBox(
      height: 84,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final url in photos)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      url,
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 84,
                        height: 84,
                        color: AppColors.primary.withValues(alpha: 0.1),
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: GestureDetector(
                      onTap: () => _removeExtraPhoto(url),
                      child: const CircleAvatar(
                        radius: 11,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (photos.length < ProfileService.maxExtraPhotos)
            InkWell(
              onTap: _uploadingPhoto
                  ? null
                  : () => _pickAndUpload(target: _PhotoTarget.extra),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.4),
                  ),
                ),
                child: const Icon(
                  Icons.add_a_photo_outlined,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _card({
    required String title,
    String? subtitle,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}
