import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/study_file_model.dart';
import '../providers/app_state.dart';
import '../services/study_file_service.dart';
import '../services/google_drive_service.dart';
import '../services/career_service.dart';
import '../utils/file_security_validator.dart';
import '../utils/input_sanitizer.dart';
import '../utils/custom_file_picker.dart';
import '../widgets/subject_group_list.dart';
import '../widgets/career_subject_picker.dart';
import '../widgets/study_file_card.dart';
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final StudyFileService _studyFileService = StudyFileService();
  bool _isUploading = false;

  /// Avance de la subida en curso, de 0 a 1.
  double _uploadProgress = 0;
  bool _isSyncing = false;

  /// Filtro de carrera de cada pestaña, por separado: null = todas. No se
  /// persiste, igual que en reuniones, para no esconder archivos por un
  /// filtro que quedó puesto de la sesión anterior.
  String? _filesCareerFilter;
  String? _materialsCareerFilter;

  /// Cuándo terminó la última sincronización automática. Volver a la app
  /// dispara una, y sin esto alternar entre ventanas la lanzaría en bucle.
  DateTime? _lastAutoSync;

  /// Cuánto se espera entre sincronizaciones automáticas.
  static const Duration _autoSyncCooldown = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Un solo sync: trabajos y material docente viven en la misma tabla.
      _syncAndCleanFiles();
    });
  }

  /// Abrir un archivo lleva a Drive, y de ahí el usuario puede volver habiendo
  /// borrado o agregado cosas. Sincronizar al volver es lo que hace que ese
  /// cambio aparezca solo, sin que tenga que arrastrar la lista ni saber que
  /// existe un botón.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    final ultima = _lastAutoSync;
    if (ultima != null &&
        DateTime.now().difference(ultima) < _autoSyncCooldown) {
      return;
    }
    _lastAutoSync = DateTime.now();
    _syncAndCleanFiles();
  }

  /// Pone la app al día: metadatos desde Supabase y cambios desde Drive.
  ///
  /// Los dos pasos corren siempre, también en la carga inicial y al volver a
  /// la app. Contrastar con Drive es una sola consulta de diferencias
  /// ([StudyFileService.syncDriveChanges]), no una por archivo, así que no hay
  /// motivo para reservarla al botón.
  ///
  /// [manual] solo decide si se confirma con un aviso: apretar el botón y no
  /// ver ninguna reacción se leía como que la app no había hecho nada.
  Future<void> _syncAndCleanFiles({bool manual = false}) async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      await _studyFileService.syncFromSupabase();
      // El botón hace el barrido completo; la automática, solo el delta. Es la
      // diferencia entre "ponme al día" y "arregla lo que esté descuadrado".
      //
      // Y solo el botón puede abrir la ventana de permisos de Google: la
      // automática se rinde antes de interrumpir. Sin eso, cada vez que se
      // abría la app aparecía sola la pantalla que dice "esta app no es
      // segura" — porque en web el token vive en memoria y se pierde al
      // recargar.
      final cambios = await _studyFileService.syncDriveChanges(
        completa: manual,
        interactivo: manual,
      );
      if (!mounted || !manual) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(cambios.resumen),
          backgroundColor:
              (cambios.fallo || cambios.ignorados > 0) ? AppColors.warning : null,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
        ),
      );
    } on DriveScopeInsufficientException {
      // El usuario autorizó la app cuando pedía el permiso acotado y no aceptó
      // el ampliado. Sin esto la sincronización fallaría en silencio y
      // parecería que Drive simplemente no tiene nada nuevo.
      //
      // Solo se avisa en la sincronización manual: el permiso se pide con un
      // popup, y los navegadores solo lo dejan abrir si viene de un clic. En
      // la automática el popup no llega a aparecer, así que el aviso sería un
      // reproche por algo que el usuario ni vio.
      if (!mounted || !manual) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bitácora necesita permiso para ver los archivos que subes '
            'directamente a Google Drive. Vuelve a intentarlo y acepta el '
            'permiso.',
          ),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 6),
        ),
      );
    } finally {
      _lastAutoSync = DateTime.now();
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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

      if (file.head.isEmpty) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('No se pudieron obtener los datos del archivo.')),
          );
        }
        return;
      }

      // 1. Validar Seguridad y Magic Bytes (basta la cabecera del archivo)
      final validation = FileSecurityValidator.validateFile(
        fileName: file.name,
        sizeInBytes: file.size,
        bytes: file.head,
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
      setState(() {
        _isUploading = true;
        _uploadProgress = 0;
      });

      final customCareerId = details['careerId'] ?? '';

      final uploadRes = await GoogleDriveService().uploadStudyFile(
        fileName: customName,
        sizeBytes: file.size,
        filePath: file.path,
        bytes: file.bytes,
        mimeType: file.extension.isNotEmpty ? file.extension : 'application/octet-stream',
        career: CareerService().careerNameFor(customCareerId),
        subject: customSubject,
        onProgress: _onUploadProgress,
      );

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
      await CustomFilePicker.clearTemporaryFiles();
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  /// Refresca el porcentaje de la subida, pero solo cada 1%.
  ///
  /// El archivo se lee del disco en bloques de decenas de KB, así que uno de
  /// 250 MB dispararía miles de `setState` y trabaría la pantalla entera.
  void _onUploadProgress(double progress) {
    if (!mounted) return;
    final avanzo = (progress - _uploadProgress).abs() >= 0.01;
    if (!avanzo && progress < 1) return;
    setState(() => _uploadProgress = progress);
  }

  /// Texto del botón mientras sube: con archivos grandes, un spinner sin
  /// información deja al usuario a ciegas varios minutos.
  String get _uploadLabel => _uploadProgress > 0
      ? 'Subiendo ${(_uploadProgress * 100).round()}%'
      : 'Subiendo...';

  Future<Map<String, String>?> _showFileDetailsDialog(String originalName) async {
    final propias = context.read<AppState>().subjects.map((s) => s.name).toList();

    String? careerId;
    String subject = '';

    final nameController = TextEditingController(text: originalName);
    final formKey = GlobalKey<FormState>();

    return showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final primaryColor = Theme.of(context).primaryColor;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.drive_folder_upload_rounded, color: primaryColor),
              const SizedBox(width: 10),
              const Text('Detalles del Archivo',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                  CareerSubjectPicker(
                    ownSubjects: propias,
                    onChanged: (c, s) {
                      careerId = c;
                      subject = s;
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
                    'name': InputSanitizer.sanitizeText(nameController.text),
                    'subject': subject,
                    // Cadena vacía = sin carrera; el mapa no admite nulos.
                    'careerId': careerId ?? '',
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
            icon: _isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            tooltip: 'Sincronizar con Google Drive',
            onPressed: _isSyncing ? null : () => _syncAndCleanFiles(manual: true),
          ),
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
            // "Mis archivos", no "Mis tareas": esta pestaña son archivos, y
            // las tareas de verdad viven en Pendientes/Vencidas/Entregadas.
            // Con el nombre anterior había dos cosas distintas llamadas igual
            // a un toque de distancia.
            Tab(icon: Icon(Icons.folder_shared_rounded), text: 'Mis archivos'),
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
              tooltip: showSpinner && _uploadProgress > 0
                  ? 'Subiendo ${(_uploadProgress * 100).round()}%'
                  : tooltip,
              child: showSpinner
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                        value: _uploadProgress > 0 ? _uploadProgress : null,
                      ),
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
          // Arrastrar es tan explícito como apretar el botón: hace el barrido
          // completo, no solo el delta. Que hicieran cosas distintas era una
          // trampa — el usuario prueba las dos y no entiende por qué una
          // arregla lo que la otra deja igual.
          onRefresh: () => _syncAndCleanFiles(manual: true),
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
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                        value: _uploadProgress > 0 ? _uploadProgress : null,
                      ),
                    )
                  : const Icon(Icons.upload_file_rounded),
              label: Text(_isUploading ? _uploadLabel : 'Subir Archivo de Estudio'),
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

  Widget _buildFileCard(StudyFile file) => StudyFileCard(
        file: file,
        onOpen: () => _openFileLink(file.driveLink, fileName: file.name),
        onEdit: () => _showEditFileDialog(file),
        onDelete: () => _confirmDelete(file),
      );

  /// Edita los datos de un archivo ya subido: nombre, materia, carrera y
  /// —en el material docente— descripción. No toca el archivo en Drive, solo
  /// sus metadatos, así que sirve para corregir una carrera mal asignada sin
  /// tener que volver a subirlo. Es además la única forma de ponerle carrera
  /// a los archivos subidos antes de que ese campo existiera.
  Future<void> _showEditFileDialog(StudyFile file) async {
    final propias = context.read<AppState>().subjects.map((s) => s.name).toList();

    // Los archivos subidos antes de que existiera el campo no tienen carrera;
    // el picker les propone la activa. Editarlos es justamente la forma de
    // terminar de clasificarlos.
    String? selectedCareerId = file.careerId;
    String selectedSubject = file.subject;

    final nameController = TextEditingController(text: file.name);
    final descriptionController =
        TextEditingController(text: file.description ?? '');
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final primaryColor = Theme.of(context).primaryColor;
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
                      const SizedBox(height: 16),
                      CareerSubjectPicker(
                        initialCareerId: selectedCareerId,
                        initialSubject: selectedSubject,
                        ownSubjects: propias,
                        onChanged: (c, sub) {
                          selectedCareerId = c;
                          selectedSubject = sub;
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
                    final description =
                        InputSanitizer.sanitizeText(descriptionController.text);
                    try {
                      await _studyFileService.saveFile(
                        StudyFile.fromMap({
                          ...file.toMap(),
                          'name': InputSanitizer.sanitizeText(nameController.text),
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
    if (confirmed != true) return;

    final driveOk = await _studyFileService.deleteStudyFile(file);
    if (mounted) _avisarBorrado(driveOk);
  }

  /// Un borrado a medias —quitado de la app pero todavía en Drive— hay que
  /// decirlo. Antes se anunciaba "eliminado" pasara lo que pasara.
  void _avisarBorrado(bool driveOk) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(driveOk
            ? 'Eliminado de la app y de Google Drive'
            : 'Eliminado de la app, pero no se pudo borrar en Google Drive'),
        backgroundColor: driveOk ? AppColors.success : AppColors.warning,
      ),
    );
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
          // La misma sincronización que en Archivos: son la misma tabla y las
          // mismas carpetas de Drive. Que esta pestaña mirara solo Supabase
          // hacía que un archivo borrado o agregado a mano en
          // `Material docente/` no apareciera nunca.
          onRefresh: () => _syncAndCleanFiles(manual: true),
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
    // El material docente puede venir de otro miembro de la carrera: solo su
    // autor lo edita o lo borra.
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;

    return StudyFileCard(
      file: material,
      canModify:
          material.userId.isNotEmpty && material.userId == currentUserId,
      onOpen: () => _openFileLink(material.openUrl, fileName: material.name),
      onEdit: () => _showEditFileDialog(material),
      onDelete: () => _confirmDeleteMaterial(material),
    );
  }

  Future<void> _confirmDeleteMaterial(StudyFile material) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('¿Eliminar material?'),
        content: Text(material.isLink
            ? '"${material.name}" se quitará de tu material docente.'
            : '"${material.name}" se eliminará de tu material docente y de tu '
                'Google Drive.'),
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
    if (confirmed != true) return;

    // El mismo borrado que en Archivos: es la misma tabla y el mismo archivo
    // de Drive. Que esta pestaña solo quitara el metadato dejaba el archivo en
    // Drive para siempre, sin que nadie lo dijera.
    final driveOk = await _studyFileService.deleteStudyFile(material);
    if (mounted) _avisarBorrado(driveOk);
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

      if (file.head.isEmpty) {
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
        bytes: file.head,
      );
      if (!validation.isValid) {
        if (mounted) {
          _showSecurityAlertDialog(validation.errorMessage ?? 'Archivo no permitido por seguridad.');
        }
        return;
      }

      final details = await _showFileDetailsDialog(file.name);
      if (details == null) return;

      setState(() {
        _isUploading = true;
        _uploadProgress = 0;
      });

      final uploadRes = await GoogleDriveService().uploadStudyFile(
        fileName: details['name']!,
        sizeBytes: file.size,
        filePath: file.path,
        bytes: file.bytes,
        mimeType: file.extension.isNotEmpty ? file.extension : 'application/octet-stream',
        career: CareerService().careerNameFor(details['careerId']),
        subject: details['subject']!,
        // Fuera de la carpeta de trabajos, para que el escaneo de Drive no
        // registre las guías también como archivos personales.
        subfolder: GoogleDriveService.teachingMaterialFolderName,
        onProgress: _onUploadProgress,
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
      await CustomFilePicker.clearTemporaryFiles();
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 0;
        });
      }
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

    final propias = context.read<AppState>().subjects.map((s) => s.name).toList();
    String? selectedCareerId;
    String selectedSubject = '';

    final titleController = TextEditingController();
    final urlController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final primaryColor = Theme.of(context).primaryColor;
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
                      CareerSubjectPicker(
                        ownSubjects: propias,
                        onChanged: (c, sub) {
                          selectedCareerId = c;
                          selectedSubject = sub;
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
                        name: InputSanitizer.sanitizeText(titleController.text),
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
