import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../auth_service.dart';
import '../colors.dart';
import '../models/career_model.dart';
import '../services/career_service.dart';
import '../services/profile_service.dart';
import '../utils/custom_file_picker.dart';
import '../utils/file_security_validator.dart';
import '../utils/input_sanitizer.dart';
import 'announcements_screen.dart';
import 'assign_task_screen.dart';
import 'attendance_screen.dart';
import 'career_attendance_screen.dart';
import 'career_grades_screen.dart';
import 'career_members_directory_screen.dart';
import 'my_attendance_screen.dart';
import 'my_grades_screen.dart';
import 'public_profile_screen.dart';
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

class _MyProfileScreenState extends State<MyProfileScreen> {
  final _service = ProfileService();
  final _careerService = CareerService();
  final _authService = AuthService();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _ageController = TextEditingController();
  final _genderController = TextEditingController();
  final _relationshipController = TextEditingController();
  final _religionController = TextEditingController();

  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;
  double _uploadProgress = 0;
  String? _error;

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
    _genderController.dispose();
    _relationshipController.dispose();
    _religionController.dispose();
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
        _genderController.text = (profile?['gender'] as String?) ?? '';
        _relationshipController.text =
            (profile?['relationship_status'] as String?) ?? '';
        _religionController.text = (profile?['religion'] as String?) ?? '';
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
        gender: InputSanitizer.sanitizeText(_genderController.text),
        relationshipStatus: InputSanitizer.sanitizeText(
          _relationshipController.text,
        ),
        religion: InputSanitizer.sanitizeText(_religionController.text),
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

  Future<void> _pickAndUpload({required bool asMainPhoto}) async {
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
                    ? 'Elegí una imagen (jpg, png, webp).'
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

      if (asMainPhoto) {
        await _service.setMainPhoto(url);
      } else {
        await _service.addExtraPhoto(url);
      }
      await _load();
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
                          const SizedBox(height: 12),
                          TextField(
                            controller: _bioController,
                            maxLines: 3,
                            maxLength: 300,
                            decoration: const InputDecoration(
                              labelText: 'Bio (opcional)',
                              hintText: 'Contá algo sobre vos',
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
                          TextField(
                            controller: _genderController,
                            decoration: const InputDecoration(
                              labelText: 'Género (opcional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _relationshipController,
                            decoration: const InputDecoration(
                              labelText: 'Situación sentimental (opcional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _religionController,
                            decoration: const InputDecoration(
                              labelText: 'Creencias / religión (opcional)',
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
                  'Qué materias impartís, para cruzar con el semestre del alumno',
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

      _sectionHeader('Estudias dos o más carreras', Icons.school_outlined),
      const SizedBox(height: 8),
      Card(
        child: Column(
          children: [
            ..._careers.map(_careerTile),
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
        ),
      ),
      const SizedBox(height: 24),

      _sectionHeader('Cuenta', Icons.manage_accounts_outlined),
      const SizedBox(height: 8),
      Card(
        child: Column(
          children: [
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
  /// ya etiquetan cada materia, para no inventar una lista aparte.
  List<String> _semestresDe(Career career) =>
      career.predefinedSubjects
          .map((s) => s.semester?.trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

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
              (s) => DropdownMenuItem<String?>(value: s, child: Text(s)),
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
    return ListTile(
      leading: Icon(
        isActive ? Icons.radio_button_checked : Icons.radio_button_off,
        color: isActive ? AppColors.primary : AppColors.textSecondary,
      ),
      title: Text(
        career.name,
        style: TextStyle(
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(isActive ? 'Carrera activa' : 'Tocar para activar'),
      trailing: _careers.length > 1
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
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        Container(
          height: 120,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        Positioned(top: 76, child: _avatarPicker(photoUrl)),
      ],
    );
  }

  Widget _avatarPicker(String? photoUrl) {
    return GestureDetector(
      onTap: _uploadingPhoto ? null : () => _pickAndUpload(asMainPhoto: true),
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              shape: BoxShape.circle,
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
          if (_uploadingPhoto)
            Positioned.fill(
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
            )
          else
            Positioned(
              right: 0,
              bottom: 0,
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
        ],
      ),
    );
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
                  : () => _pickAndUpload(asMainPhoto: false),
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
