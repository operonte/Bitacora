import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/study_file_model.dart';
import '../models/teaching_material_model.dart';
import '../services/study_file_service.dart';
import '../services/teaching_material_service.dart';
import '../services/google_drive_service.dart';
import '../services/career_service.dart';
import '../utils/file_security_validator.dart';
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
  final TeachingMaterialService _teachingMaterialService = TeachingMaterialService();
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncAndCleanFiles();
      _teachingMaterialService.syncFromSupabase();
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

      final studyFile = StudyFile(
        name: customName,
        subject: customSubject,
        driveFileId: uploadRes.fileId,
        mimeType: file.extension.isNotEmpty ? file.extension : 'file',
        sizeBytes: file.size,
        driveLink: uploadRes.webViewLink,
        userId: user.id,
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

  Future<Map<String, String>?> _showFileDetailsDialog(String originalName) async {
    final careers = CareerService().getCareers();
    final List<String> subjects = ['General'];
    for (final c in careers) {
      for (final s in c.predefinedSubjects) {
        if (!subjects.contains(s.name)) {
          subjects.add(s.name);
        }
      }
    }
    
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
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: subjects.contains(selectedSubject) ? selectedSubject : subjects.first,
                        decoration: InputDecoration(
                          labelText: 'Asignatura / Materia',
                          prefixIcon: const Icon(Icons.school_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: subjects.map((sub) {
                          return DropdownMenuItem<String>(
                            value: sub,
                            child: Text(sub, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
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
              '${file.subject} \u2022 ${file.formattedSize}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
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
                final link = await GoogleDriveService().makeFilePubliclySharable(file.driveFileId);
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
                final link = await GoogleDriveService().makeFilePubliclySharable(file.driveFileId);
                await Share.share(
                  '\u00abBit\u00e1cora\u00bb \u2022 ${file.name}\n$link',
                  subject: file.name,
                );
              },
            ),
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

  Widget _buildFilesTab(dynamic career) {
    return ListenableBuilder(
      listenable: _studyFileService,
      builder: (context, _) {
        final allFiles = _studyFileService.getFiles();

        if (allFiles.isEmpty) {
          return _buildEmptyFilesState();
        }

        return RefreshIndicator(
          onRefresh: () => _syncAndCleanFiles(),
          child: SubjectGroupList<StudyFile>(
            items: allFiles,
            subjectOf: (f) => f.subject,
            countLabelOf: (count) => '$count ${count == 1 ? 'archivo' : 'archivos'}',
            itemBuilder: _buildFileCard,
            dateOf: (f) => f.createdAt,
            dateDescending: true,
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
              // Acciones: Compartir y Eliminar
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
      if (driveId.isNotEmpty) {
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
      listenable: _teachingMaterialService,
      builder: (context, _) {
        final materials = _teachingMaterialService.getMaterials();

        if (materials.isEmpty) {
          return _buildEmptyMaterialsState();
        }

        return RefreshIndicator(
          onRefresh: () => _teachingMaterialService.syncFromSupabase(),
          child: SubjectGroupList<TeachingMaterial>(
            items: materials,
            subjectOf: (m) => m.subject,
            countLabelOf: (count) => '$count ${count == 1 ? 'material' : 'materiales'}',
            itemBuilder: _buildMaterialCard,
            dateOf: (m) => m.createdAt,
            dateDescending: true,
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
              'Comparte con todo tu curso los archivos o enlaces que te envíe un profesor.',
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

  Widget _buildMaterialCard(TeachingMaterial material) {
    final primaryColor = Theme.of(context).primaryColor;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final canDelete = material.userId.isNotEmpty && material.userId == currentUserId;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openFileLink(material.openUrl, fileName: material.title),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: material.materialColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(material.materialIcon, color: material.materialColor, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      material.title,
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
                          child: Text(
                            'Subido por ${material.userName}',
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
              if (canDelete)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.error),
                  tooltip: 'Eliminar',
                  onPressed: () => _confirmDeleteMaterial(material),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteMaterial(TeachingMaterial material) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿Eliminar material?'),
        content: Text('"${material.title}" dejará de verse para todo el curso.'),
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
      await _teachingMaterialService.deleteMaterial(material.id!);
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

  String? _currentUserDisplayName(User user) =>
      user.userMetadata?['full_name'] as String? ?? user.email;

  Future<void> _addMaterialFile() async {
    final messenger = ScaffoldMessenger.of(context);
    final user = Supabase.instance.client.auth.currentUser;
    final career = CareerService().getSelectedCareer();
    if (user == null || career == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Debes tener una carrera seleccionada para publicar material.')),
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
      );
      // Los compañeros de curso no son dueños de este Drive: sin hacerlo
      // público por link, no podrían abrir el archivo.
      await GoogleDriveService().makeFilePubliclySharable(uploadRes.fileId);

      final material = TeachingMaterial(
        careerId: career.id,
        subject: details['subject']!,
        title: details['name']!,
        type: 'file',
        driveFileId: uploadRes.fileId,
        driveLink: uploadRes.webViewLink,
        mimeType: file.extension,
        sizeBytes: file.size,
        userId: user.id,
        userName: _currentUserDisplayName(user) ?? 'Usuario',
      );
      await _teachingMaterialService.addMaterial(material);

      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('✅ Material publicado para el curso'),
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
    final career = CareerService().getSelectedCareer();
    if (user == null || career == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Debes tener una carrera seleccionada para publicar material.')),
        );
      }
      return;
    }

    final careers = CareerService().getCareers();
    final List<String> subjects = ['General'];
    for (final c in careers) {
      for (final s in c.predefinedSubjects) {
        if (!subjects.contains(s.name)) subjects.add(s.name);
      }
    }
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
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: subjects.contains(selectedSubject) ? selectedSubject : subjects.first,
                        decoration: InputDecoration(
                          labelText: 'Asignatura / Materia',
                          prefixIcon: const Icon(Icons.school_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        items: subjects.map((sub) {
                          return DropdownMenuItem<String>(
                            value: sub,
                            child: Text(sub, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedSubject = val);
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
                      final material = TeachingMaterial(
                        careerId: career.id,
                        subject: selectedSubject,
                        title: titleController.text.trim(),
                        type: 'link',
                        externalUrl: urlController.text.trim(),
                        userId: user.id,
                        userName: _currentUserDisplayName(user) ?? 'Usuario',
                      );
                      await _teachingMaterialService.addMaterial(material);
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
          content: Text('✅ Material publicado para el curso'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }
}
