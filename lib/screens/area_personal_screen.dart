import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/study_file_model.dart';
import '../services/study_file_service.dart';
import '../services/google_drive_service.dart';
import '../services/career_service.dart';
import '../utils/file_security_validator.dart';
import '../utils/input_sanitizer.dart';
import '../utils/custom_file_picker.dart';
import '../widgets/subject_group_list.dart';
import 'meetings_screen.dart';
import 'add_meeting_screen.dart';
import 'config_screen.dart';
import '../colors.dart';

class AreaPersonalScreen extends StatefulWidget {
  const AreaPersonalScreen({super.key});

  @override
  State<AreaPersonalScreen> createState() => _AreaPersonalScreenState();
}

class _AreaPersonalScreenState extends State<AreaPersonalScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final StudyFileService _studyFileService = StudyFileService();
  bool _isUploading = false;

  /// Filtro de carrera de cada pestaña, por separado: null = todas. No se
  /// persiste, igual que en reuniones, para no esconder archivos por un
  /// filtro que quedó puesto de la sesión anterior.
  String? _filesCareerFilter;
  String? _materialsCareerFilter;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Un solo sync: trabajos y material docente viven en la misma tabla.
      _syncAndCleanFiles();
    });
  }

  Future<void> _syncAndCleanFiles() async {
    await _studyFileService.syncFromSupabaseAndDrive(
      onNotify: (msg) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: AppColors.primary,
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadFile() async {
    final messenger = ScaffoldMessenger.of(context);
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Debes iniciar sesión para subir archivos.')),
      );
      return;
    }

    try {
      final file = await CustomFilePicker.pickFile();
      if (file == null) return;

      final bytes = file.bytes;
      if (bytes.isEmpty) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('No se pudieron obtener los datos del archivo.')),
          );
        }
        return;
      }

      // 1. Validar Seguridad y Magic Bytes
      final validation = FileSecurityValidator.validateFile(
        fileName: file.name,
        sizeInBytes: file.size,
        bytes: bytes,
      );

      if (!validation.isValid) {
        if (mounted) {
          _showSecurityAlertDialog(validation.errorMessage ?? 'Archivo no permitido por seguridad.');
        }
        return;
      }

      // 2. Diálogo para definir Nombre y Asignatura del documento
      final details = await _showFileDetailsDialog(file.name);
      if (details == null) return; // Cancelado por el usuario

      final customName = details['name']!;
      final customSubject = details['subject']!;

      // 3. Proceder con la subida a Google Drive
      setState(() => _isUploading = true);

      final uploadRes = await GoogleDriveService().uploadStudyFile(
        fileName: customName,
        bytes: bytes,
        mimeType: file.extension.isNotEmpty ? file.extension : 'application/octet-stream',
        subject: customSubject,
      );

      final customCareerId = details['careerId'] ?? '';

      final studyFile = StudyFile(
        name: customName,
        subject: customSubject,
        driveFileId: uploadRes.fileId,
        mimeType: file.extension.isNotEmpty ? file.extension : 'file',
        sizeBytes: file.size,
        driveLink: uploadRes.webViewLink,
        userId: user.id,
        careerId: customCareerId.isEmpty ? null : customCareerId,
      );

      await _studyFileService.saveFile(studyFile);

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('¡"${file.name}" guardado exitosamente!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  /// Materias que se pueden elegir para [careerId]. Con una carrera elegida
  /// solo se ofrecen las suyas: mezclar las de todas dejaba guardar un
  /// archivo de Informática con una asignatura de Teología. Sin carrera se
  /// ofrecen todas, porque ahí no hay nada que acote.
  List<String> _subjectsForCareer(String? careerId) {
    final subjects = <String>['General'];
    for (final c in CareerService().getCareers()) {
      if (careerId != null && c.id != careerId) continue;
      for (final s in c.predefinedSubjects) {
        if (!subjects.contains(s.name)) subjects.add(s.name);
      }
    }
    return subjects;
  }

  Future<Map<String, String>?> _showFileDetailsDialog(String originalName) async {
    final careers = CareerService().getCareers();
    String? selectedCareerId = CareerService().getSelectedCareer()?.id;
    List<String> subjects = _subjectsForCareer(selectedCareerId);
    String selectedSubject = subjects.length > 1 ? subjects[1] : 'General';

    final nameController = TextEditingController(text: originalName);
    final formKey = GlobalKey<FormState>();

    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final primaryColor = Theme.of(context).primaryColor;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(Icons.drive_folder_upload_rounded, color: primaryColor),
                  const SizedBox(width: 10),
                  const Text('Detalles del Archivo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Asigna un nombre y la asignatura correspondiente a este archivo:',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: 'Nombre del archivo',
                          prefixIcon: const Icon(Icons.description_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Ingresa un nombre para el archivo';
                          }
                          return null;
                        },
                      ),
                      if (careers.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String?>(
                          initialValue: careers.any((c) => c.id == selectedCareerId)
                              ? selectedCareerId
                              : null,
                          decoration: InputDecoration(
                            labelText: 'Carrera',
                            prefixIcon: const Icon(Icons.workspace_premium_outlined),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Sin carrera'),
                            ),
                            for (final c in careers)
                              DropdownMenuItem<String?>(
                                value: c.id,
                                child: Text(c.name, overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (val) => setDialogState(() {
                            selectedCareerId = val;
                            // La materia elegida puede no existir en la
                            // carrera nueva: se recalcula la lista y, si ya
                            // no calza, se vuelve a la primera.
                            subjects = _subjectsForCareer(val);
                            if (!subjects.contains(selectedSubject)) {
                              selectedSubject =
                                  subjects.length > 1 ? subjects[1] : subjects.first;
                            }
                          }),
                        ),
                      ],
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: subjects.contains(selectedSubject)
                            ? selectedSubject
                            : subjects.first,
                        decoration: InputDecoration(
                          labelText: 'Asignatura / Materia',
                          prefixIcon: const Icon(Icons.school_outlined),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        items: subjects
                            .map((sub) => DropdownMenuItem<String>(
                                  value: sub,
                                  child:
                                      Text(sub, overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedSubject = val);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Navigator.pop(ctx, {
                        'name': nameController.text.trim(),
                        'subject': selectedSubject,
                        // Cadena vacía = sin carrera; el mapa no admite nulos.
                        'careerId': selectedCareerId ?? '',
                      });
                    }
                  },
                  style: FilledButton.styleFrom(backgroundColor: primaryColor),
                  icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                  label: const Text('Subir Archivo'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showSecurityAlertDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.shield_outlined, color: AppColors.error),
            SizedBox(width: 8),
            Text('Filtro de Seguridad'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  void _showShareOptions(StudyFile file) {
    final driveId = file.driveFileId;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              file.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              [file.subject, file.formattedSize]
                  .where((s) => s.isNotEmpty)
                  .join(' \u2022 '),
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            // Compartir por link solo aplica a archivos que viven en Drive:
            // un material que es un enlace externo ya es un link.
            if (driveId != null && driveId.isNotEmpty) ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.copy_rounded, color: AppColors.primary, size: 22),
              ),
              title: const Text('Copiar enlace', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Comparte el enlace de este archivo'),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                Navigator.pop(ctx);
                final link = await GoogleDriveService().makeFilePubliclySharable(driveId);
                await Clipboard.setData(ClipboardData(text: link));
                messenger.showSnackBar(
                  const SnackBar(content: Text('\u00a1Enlace copiado!')),
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.share_rounded, color: Colors.green, size: 22),
              ),
              title: const Text('Enviar a...', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Abre el men\u00fa nativo para compartir'),
              onTap: () async {
                Navigator.pop(ctx);
                final link = await GoogleDriveService().makeFilePubliclySharable(driveId);
                await Share.share(
                  '\u00abBit\u00e1cora\u00bb \u2022 ${file.name}\n$link',
                  subject: file.name,
                );
              },
            ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openFileLink(String url, {String? fileName}) async {
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este archivo no tiene enlace disponible.')),
      );
      return;
    }

    // El enlace externo lo escribe el usuario, así que no se le pasa a
    // launchUrl sin comprobar el esquema: solo http/https.
    if (!InputSanitizer.isSafeExternalUrl(url)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El enlace no es válido (solo se admite http o https).')),
      );
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return;

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      try {
        await launchUrl(uri);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo abrir el archivo: $e')),
          );
        }
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final career = CareerService().getSelectedCareer();
    final careerName = career?.name ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mi área'),
            if (careerName.isNotEmpty)
              Text(
                careerName,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.normal,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ConfigScreen()),
            ),
            tooltip: 'Configuración',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(icon: Icon(Icons.folder_shared_rounded), text: 'Mis tareas'),
            Tab(icon: Icon(Icons.video_camera_front_rounded), text: 'Mis reuniones'),
            Tab(icon: Icon(Icons.menu_book_rounded), text: 'Material docente'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFilesTab(career),
          const MeetingsScreen(isEmbedded: true),
          _buildTeachingMaterialsTab(career),
        ],
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabController,
        builder: (context, child) {
          final tabIndex = _tabController.index;

          String tooltip;
          VoidCallback? onPressed;
          if (tabIndex == 0) {
            tooltip = 'Subir archivo';
            onPressed = _isUploading ? null : () => _pickAndUploadFile();
          } else if (tabIndex == 1) {
            tooltip = 'Nueva reunión';
            onPressed = () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddMeetingScreen()),
                );
          } else {
            tooltip = 'Agregar material docente';
            onPressed = _isUploading ? null : () => _showAddMaterialDialog();
          }

          final showSpinner = _isUploading && tabIndex != 1;

          return Padding(
            padding: const EdgeInsets.only(bottom: 75),
            child: FloatingActionButton(
              onPressed: onPressed,
              backgroundColor: Theme.of(context).primaryColor,
              elevation: 4,
              shape: const CircleBorder(),
              tooltip: tooltip,
              child: showSpinner
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.add,
                      color: Colors.white,
                      size: 26,
                    ),
            ),
          );
        },
      ),
    );
  }

  /// Desplegable de carrera de una pestaña de archivos. Igual que en
  /// reuniones, solo se muestra si hay más de una opción real: con una sola
  /// carrera el filtro no filtraría nada y sería solo ruido.
  Widget? _buildFilesCareerFilter({
    required String category,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    final used = _studyFileService.usedCareerIds(category);
    if (used.length < 2) return null;

    final careers = CareerService().getCareers();
    String labelFor(String id) {
      if (id == StudyFileService.noCareerFilter) return 'Sin carrera';
      for (final c in careers) {
        if (c.id == id) return c.name;
      }
      return id;
    }

    final options = used.toList()
      ..sort((a, b) => labelFor(a).compareTo(labelFor(b)));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String?>(
        initialValue: value,
        isDense: true,
        decoration: InputDecoration(
          labelText: 'Carrera',
          prefixIcon: const Icon(Icons.school_outlined, size: 20),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
        items: [
          const DropdownMenuItem<String?>(
            value: null,
            child: Text('Todas las carreras'),
          ),
          for (final id in options)
            DropdownMenuItem<String?>(value: id, child: Text(labelFor(id))),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildFilesTab(dynamic career) {
    return ListenableBuilder(
      listenable: _studyFileService,
      builder: (context, _) {
        // El vacío se decide sin el filtro puesto: si hay archivos pero el
        // filtro no selecciona ninguno, hay que seguir mostrando el
        // desplegable para poder quitarlo.
        if (_studyFileService.getFiles().isEmpty) {
          return _buildEmptyFilesState();
        }

        final files = _studyFileService.getFiles(careerId: _filesCareerFilter);

        return RefreshIndicator(
          onRefresh: () => _syncAndCleanFiles(),
          child: SubjectGroupList<StudyFile>(
            items: files,
            header: _buildFilesCareerFilter(
              category: StudyFileCategory.trabajo,
              value: _filesCareerFilter,
              onChanged: (v) => setState(() => _filesCareerFilter = v),
            ),
            subjectOf: (f) => f.subject,
            countLabelOf: (count) => '$count ${count == 1 ? 'archivo' : 'archivos'}',
            itemBuilder: _buildFileCard,
            dateOf: (f) => f.createdAt,
            dateDescending: true,
            searchHint: 'Buscar archivo o materia',
            searchTextOf: (f) => '${f.name} ${f.subject}',
          ),
        );
      },
    );
  }

  Widget _buildEmptyFilesState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_upload_outlined,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Aún no tienes archivos subidos',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Sube tus guías PDF, apuntes, resúmenes o audios.\nSe guardarán sincronizados en tu Google Drive.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _isUploading ? null : _pickAndUploadFile,
              icon: _isUploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.upload_file_rounded),
              label: Text(_isUploading ? 'Subiendo...' : 'Subir Archivo de Estudio'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileCard(StudyFile file) {
    final primaryColor = Theme.of(context).primaryColor;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openFileLink(file.driveLink, fileName: file.name),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Icono del tipo de archivo
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: file.fileColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(file.fileIcon, color: file.fileColor, size: 26),
              ),
              const SizedBox(width: 12),
              // Nombre y metadatos
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        // Badge de Asignatura
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            file.subject.isNotEmpty ? file.subject : 'General',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: primaryColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Fecha y Tamaño
                        Expanded(
                          child: Text(
                            '${DateFormat('dd/MM/yy HH:mm').format(file.createdAt)} \u2022 ${file.formattedSize}',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Acciones: Editar, Compartir y Eliminar
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                tooltip: 'Editar',
                onPressed: () => _showEditFileDialog(file),
              ),
              IconButton(
                icon: Icon(Icons.share_rounded, size: 20, color: primaryColor),
                tooltip: 'Compartir',
                onPressed: () => _showShareOptions(file),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.error),
                tooltip: 'Eliminar',
                onPressed: () => _confirmDelete(file),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Edita los datos de un archivo ya subido: nombre, materia, carrera y
  /// —en el material docente— descripción. No toca el archivo en Drive, solo
  /// sus metadatos, así que sirve para corregir una carrera mal asignada sin
  /// tener que volver a subirlo. Es además la única forma de ponerle carrera
  /// a los archivos subidos antes de que ese campo existiera.
  Future<void> _showEditFileDialog(StudyFile file) async {
    final careers = CareerService().getCareers();
    String? selectedCareerId =
        careers.any((c) => c.id == file.careerId) ? file.careerId : null;
    List<String> subjects = _subjectsForCareer(selectedCareerId);
    // La materia guardada puede no estar en la carrera (archivo viejo, mal
    // clasificado, o carrera de la que el usuario se salió): se agrega para
    // no perderla al abrir el desplegable.
    if (file.subject.isNotEmpty && !subjects.contains(file.subject)) {
      subjects.insert(1, file.subject);
    }

    String selectedSubject =
        subjects.contains(file.subject) ? file.subject : subjects.first;

    final nameController = TextEditingController(text: file.name);
    final descriptionController =
        TextEditingController(text: file.description ?? '');
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final primaryColor = Theme.of(context).primaryColor;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(Icons.edit_outlined, color: primaryColor),
                  const SizedBox(width: 10),
                  const Text('Editar',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: 'Nombre',
                          prefixIcon: const Icon(Icons.description_outlined),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) =>
                            (val == null || val.trim().isEmpty)
                                ? 'Ingresa un nombre'
                                : null,
                      ),
                      if (file.isGuia) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: descriptionController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Descripción (opcional)',
                            prefixIcon: const Icon(Icons.notes_rounded),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                      if (careers.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String?>(
                          initialValue: selectedCareerId,
                          decoration: InputDecoration(
                            labelText: 'Carrera',
                            prefixIcon:
                                const Icon(Icons.workspace_premium_outlined),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Sin carrera'),
                            ),
                            for (final c in careers)
                              DropdownMenuItem<String?>(
                                value: c.id,
                                child: Text(c.name,
                                    overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (val) => setDialogState(() {
                            selectedCareerId = val;
                            subjects = _subjectsForCareer(val);
                            if (!subjects.contains(selectedSubject)) {
                              selectedSubject = subjects.length > 1
                                  ? subjects[1]
                                  : subjects.first;
                            }
                          }),
                        ),
                      ],
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: subjects.contains(selectedSubject)
                            ? selectedSubject
                            : subjects.first,
                        decoration: InputDecoration(
                          labelText: 'Asignatura / Materia',
                          prefixIcon: const Icon(Icons.school_outlined),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        items: subjects
                            .map((sub) => DropdownMenuItem<String>(
                                  value: sub,
                                  child: Text(sub,
                                      overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedSubject = val);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    final description = descriptionController.text.trim();
                    try {
                      await _studyFileService.saveFile(
                        StudyFile.fromMap({
                          ...file.toMap(),
                          'name': nameController.text.trim(),
                          'subject': selectedSubject,
                          'career_id': selectedCareerId,
                          // Vacío borra la descripción; solo el material
                          // docente muestra el campo, el resto la conserva.
                          'description':
                              file.isGuia ? description : file.description,
                        }),
                      );
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('Error al guardar: $e'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    }
                  },
                  style: FilledButton.styleFrom(backgroundColor: primaryColor),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cambios guardados'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _confirmDelete(StudyFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('\u00bfEliminar archivo?'),
        content: Text('"${file.name}" ser\u00e1 eliminado de tu Google Drive y de la app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final fileId = file.id;
      final driveId = file.driveFileId;
      if (fileId != null && fileId.isNotEmpty) {
        await _studyFileService.deleteFile(fileId);
      }
      if (driveId != null && driveId.isNotEmpty) {
        await _studyFileService.deleteFile(driveId);
        await GoogleDriveService().deleteFile(driveId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Archivo eliminado')),
        );
      }
    }
  }

  // ==================== MATERIAL DOCENTE ====================

  Widget _buildTeachingMaterialsTab(dynamic career) {
    return ListenableBuilder(
      listenable: _studyFileService,
      builder: (context, _) {
        if (_studyFileService
            .getFiles(category: StudyFileCategory.guia)
            .isEmpty) {
          return _buildEmptyMaterialsState();
        }

        final materials = _studyFileService.getFiles(
          category: StudyFileCategory.guia,
          careerId: _materialsCareerFilter,
        );

        return RefreshIndicator(
          onRefresh: () => _studyFileService.syncFromSupabase(),
          child: SubjectGroupList<StudyFile>(
            items: materials,
            header: _buildFilesCareerFilter(
              category: StudyFileCategory.guia,
              value: _materialsCareerFilter,
              onChanged: (v) => setState(() => _materialsCareerFilter = v),
            ),
            subjectOf: (m) => m.subject,
            countLabelOf: (count) => '$count ${count == 1 ? 'material' : 'materiales'}',
            itemBuilder: _buildMaterialCard,
            dateOf: (m) => m.createdAt,
            dateDescending: true,
            searchHint: 'Buscar material o materia',
            searchTextOf: (m) => '${m.name} ${m.subject} ${m.description ?? ''}',
          ),
        );
      },
    );
  }

  Widget _buildEmptyMaterialsState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.menu_book_outlined,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Aún no hay material docente',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Guarda acá las guías, apuntes o enlaces que te envíe un profesor.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _showAddMaterialDialog,
              icon: const Icon(Icons.add_link_rounded),
              label: const Text('Agregar material'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMaterialCard(StudyFile material) {
    final primaryColor = Theme.of(context).primaryColor;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final canDelete = material.userId.isNotEmpty && material.userId == currentUserId;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openFileLink(material.openUrl, fileName: material.name),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: material.fileColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(material.fileIcon, color: material.fileColor, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      material.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            material.isLink ? 'Enlace' : 'Archivo',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: primaryColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          // El material ya no se comparte con el curso, así que
                          // el autor sobra: siempre es el propio usuario.
                          child: Text(
                            [
                              DateFormat('d MMM y', 'es').format(material.createdAt),
                              if (material.formattedSize.isNotEmpty) material.formattedSize,
                            ].join(' · '),
                            style: TextStyle(
                              fontSize: 11,
                              color: context.isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (canDelete) ...[
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Editar',
                  onPressed: () => _showEditFileDialog(material),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.error),
                  tooltip: 'Eliminar',
                  onPressed: () => _confirmDeleteMaterial(material),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteMaterial(StudyFile material) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿Eliminar material?'),
        content: Text('"${material.name}" se quitará de tu material docente.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed == true && material.id != null) {
      await _studyFileService.deleteFile(material.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Material eliminado')),
        );
      }
    }
  }

  Future<void> _showAddMaterialDialog() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Agregar material docente'),
        content: const Text('¿El profesor te envió un archivo o un enlace?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'link'),
            child: const Text('Enlace'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'file'),
            child: const Text('Archivo'),
          ),
        ],
      ),
    );

    if (choice == 'file') {
      await _addMaterialFile();
    } else if (choice == 'link') {
      await _addMaterialLink();
    }
  }


  Future<void> _addMaterialFile() async {
    final messenger = ScaffoldMessenger.of(context);
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Debes iniciar sesión para guardar material.')),
      );
      return;
    }

    try {
      final file = await CustomFilePicker.pickFile();
      if (file == null) return;

      final bytes = file.bytes;
      if (bytes.isEmpty) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('No se pudieron obtener los datos del archivo.')),
          );
        }
        return;
      }

      final validation = FileSecurityValidator.validateFile(
        fileName: file.name,
        sizeInBytes: file.size,
        bytes: bytes,
      );
      if (!validation.isValid) {
        if (mounted) {
          _showSecurityAlertDialog(validation.errorMessage ?? 'Archivo no permitido por seguridad.');
        }
        return;
      }

      final details = await _showFileDetailsDialog(file.name);
      if (details == null) return;

      setState(() => _isUploading = true);

      final uploadRes = await GoogleDriveService().uploadStudyFile(
        fileName: details['name']!,
        bytes: bytes,
        mimeType: file.extension.isNotEmpty ? file.extension : 'application/octet-stream',
        subject: details['subject']!,
        // Fuera de la carpeta de trabajos, para que el escaneo de Drive no
        // registre las guías también como archivos personales.
        subfolder: GoogleDriveService.teachingMaterialFolderName,
      );

      final materialCareerId = details['careerId'] ?? '';
      final material = StudyFile(
        subject: details['subject']!,
        name: details['name']!,
        driveFileId: uploadRes.fileId,
        driveLink: uploadRes.webViewLink,
        mimeType: file.extension,
        sizeBytes: file.size,
        userId: user.id,
        category: StudyFileCategory.guia,
        careerId: materialCareerId.isEmpty ? null : materialCareerId,
      );
      await _studyFileService.saveFile(material);

      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('✅ Material guardado'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _addMaterialLink() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Debes iniciar sesión para guardar material.')),
        );
      }
      return;
    }

    final careers = CareerService().getCareers();
    String? selectedCareerId = CareerService().getSelectedCareer()?.id;
    List<String> subjects = _subjectsForCareer(selectedCareerId);
    String selectedSubject = subjects.length > 1 ? subjects[1] : 'General';

    final titleController = TextEditingController();
    final urlController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final primaryColor = Theme.of(context).primaryColor;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Icon(Icons.link_rounded, color: primaryColor),
                  const SizedBox(width: 10),
                  const Text('Agregar enlace', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: titleController,
                        decoration: InputDecoration(
                          labelText: 'Título',
                          prefixIcon: const Icon(Icons.title),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) =>
                            (val == null || val.trim().isEmpty) ? 'Ingresa un título' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: urlController,
                        decoration: InputDecoration(
                          labelText: 'Enlace (URL)',
                          hintText: 'https://...',
                          prefixIcon: const Icon(Icons.link),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        validator: (val) {
                          final uri = Uri.tryParse(val?.trim() ?? '');
                          if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
                            return 'Ingresa un enlace válido (https://...)';
                          }
                          return null;
                        },
                      ),
                      if (careers.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String?>(
                          initialValue: careers.any((c) => c.id == selectedCareerId)
                              ? selectedCareerId
                              : null,
                          decoration: InputDecoration(
                            labelText: 'Carrera',
                            prefixIcon: const Icon(Icons.workspace_premium_outlined),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Sin carrera'),
                            ),
                            for (final c in careers)
                              DropdownMenuItem<String?>(
                                value: c.id,
                                child: Text(c.name, overflow: TextOverflow.ellipsis),
                              ),
                          ],
                          onChanged: (val) => setDialogState(() {
                            selectedCareerId = val;
                            subjects = _subjectsForCareer(val);
                            if (!subjects.contains(selectedSubject)) {
                              selectedSubject = subjects.length > 1
                                  ? subjects[1]
                                  : subjects.first;
                            }
                          }),
                        ),
                      ],
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: subjects.contains(selectedSubject)
                            ? selectedSubject
                            : subjects.first,
                        decoration: InputDecoration(
                          labelText: 'Asignatura / Materia',
                          prefixIcon: const Icon(Icons.school_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: subjects
                            .map((sub) => DropdownMenuItem<String>(
                                  value: sub,
                                  child: Text(sub, overflow: TextOverflow.ellipsis),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() => selectedSubject = val);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: () async {
                    if (!formKey.currentState!.validate()) return;
                    try {
                      final material = StudyFile(
                        subject: selectedSubject,
                        name: titleController.text.trim(),
                        externalUrl: urlController.text.trim(),
                        userId: user.id,
                        category: StudyFileCategory.guia,
                        careerId: selectedCareerId,
                      );
                      await _studyFileService.saveFile(material);
                      if (ctx.mounted) Navigator.pop(ctx, true);
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('Error al guardar: $e'),
                            backgroundColor: AppColors.error,
                          ),
                        );
                      }
                    }
                  },
                  style: FilledButton.styleFrom(backgroundColor: primaryColor),
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Material guardado'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }
}
