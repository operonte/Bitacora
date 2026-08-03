import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/study_file_model.dart';
import '../utils/logger.dart';
import 'google_drive_service.dart';

class StudyFileService extends ChangeNotifier {
  static final StudyFileService _instance = StudyFileService._internal();
  factory StudyFileService() => _instance;
  StudyFileService._internal();

  static const String _boxName = 'study_files_box';

  /// Caja del antiguo TeachingMaterialService. Su contenido se absorbe una
  /// sola vez en [init] y después se borra.
  static const String _legacyMaterialsBoxName = 'teaching_materials_box';

  Box? _filesBox;

  Future<void> init() async {
    try {
      _filesBox = await Hive.openBox(_boxName);
      await _migrateLegacyTeachingMaterials();
      Logger.info('StudyFileService inicializado', tag: 'StudyFileService');
    } catch (e) {
      Logger.error('Error inicializando StudyFileService: $e', error: e, tag: 'StudyFileService');
    }
  }

  /// El material docente vivía en su propia caja y su propio modelo. Ahora es
  /// un StudyFile con category 'guia'; esto arrastra lo que hubiera quedado
  /// guardado localmente para que el usuario no lo pierda de vista.
  Future<void> _migrateLegacyTeachingMaterials() async {
    if (!await Hive.boxExists(_legacyMaterialsBoxName)) return;

    try {
      final legacyBox = await Hive.openBox(_legacyMaterialsBoxName);
      var migrated = 0;

      for (final value in legacyBox.values) {
        if (value is! Map) continue;
        final map = Map<String, dynamic>.from(value);
        // El modelo viejo usaba 'title' donde éste usa 'name'; fromMap ya
        // contempla los dos, solo hay que marcar la categoría.
        map['category'] = StudyFileCategory.guia;
        final file = StudyFile.fromMap(map);
        if (file.id == null) continue;
        await _filesBox?.put(file.id, file.toMap());
        migrated++;
      }

      await legacyBox.deleteFromDisk();
      if (migrated > 0) {
        Logger.info('Material docente migrado a archivos de estudio: $migrated', tag: 'StudyFileService');
      }
    } catch (e) {
      Logger.warning('No se pudo migrar la caché de material docente: $e', tag: 'StudyFileService');
    }
  }

  /// Archivos en caché de la categoría pedida, del usuario actual.
  ///
  /// El filtro por usuario importa: la caja de Hive sobrevive al cierre de
  /// sesión, así que sin él una cuenta vería los archivos de la anterior.
  List<StudyFile> getFiles({String category = StudyFileCategory.trabajo}) {
    if (_filesBox == null) return [];
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;

      return _filesBox!.values
          .map((e) {
            if (e is Map) {
              return StudyFile.fromMap(Map<String, dynamic>.from(e));
            }
            return null;
          })
          .whereType<StudyFile>()
          .where((f) => f.category == category)
          .where((f) => userId == null || f.userId.isEmpty || f.userId == userId)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      Logger.error('Error parseando archivos de estudio: $e', tag: 'StudyFileService');
      return [];
    }
  }

  /// Todos los archivos en caché, sin filtrar por categoría. Para la
  /// sincronización, que trabaja sobre el conjunto completo.
  List<StudyFile> _allCachedFiles() {
    if (_filesBox == null) return [];
    return _filesBox!.values
        .map((e) => e is Map ? StudyFile.fromMap(Map<String, dynamic>.from(e)) : null)
        .whereType<StudyFile>()
        .toList();
  }

  Future<void> saveFile(StudyFile file) async {
    final user = Supabase.instance.client.auth.currentUser;
    final fileId = file.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final fileToSave = StudyFile.fromMap({...file.toMap(), 'id': fileId});

    if (user != null) {
      try {
        final payload = fileToSave.toMap();
        payload['user_id'] = user.id;

        await Supabase.instance.client
            .from('study_files')
            .upsert(payload, onConflict: 'id');
      } catch (e) {
        Logger.error('Error guardando metadato de archivo en Supabase: $e', error: e, tag: 'StudyFileService');
      }
    }

    await _filesBox?.put(fileId, fileToSave.toMap());
    notifyListeners();
  }

  Future<void> deleteFile(String fileIdOrDriveId) async {
    if (_filesBox != null) {
      final keysToDelete = <dynamic>[];
      for (final key in _filesBox!.keys) {
        final val = _filesBox!.get(key);
        if (val is Map) {
          if (val['id'] == fileIdOrDriveId ||
              val['drive_file_id'] == fileIdOrDriveId ||
              key.toString() == fileIdOrDriveId) {
            keysToDelete.add(key);
          }
        }
      }
      for (final k in keysToDelete) {
        await _filesBox?.delete(k);
      }
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        await Supabase.instance.client
            .from('study_files')
            .delete()
            .or('id.eq.$fileIdOrDriveId,drive_file_id.eq.$fileIdOrDriveId');
      } catch (e) {
        Logger.warning('No se pudo borrar metadato de archivo remoto: $e', tag: 'StudyFileService');
      }
    }
    notifyListeners();
  }

  Future<void> syncFromSupabase() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      // 1. Subir metadatos locales a Supabase
      final localFiles = _allCachedFiles();
      for (final f in localFiles) {
        try {
          final payload = f.toMap();
          payload['user_id'] = user.id;
          await Supabase.instance.client
              .from('study_files')
              .upsert(payload, onConflict: 'id');
        } catch (err) {
          Logger.warning('No se pudo respaldar metadato de archivo en Supabase: $err', tag: 'StudyFileService');
        }
      }

      // 2. Traer la lista oficial desde Supabase y sincronizar la memoria local
      final List<dynamic> response = await Supabase.instance.client
          .from('study_files')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      final remoteIds = <String>{};
      for (final item in response) {
        if (item is Map) {
          final sf = StudyFile.fromMap(Map<String, dynamic>.from(item));
          if (sf.id != null) {
            remoteIds.add(sf.id!);
            await _filesBox?.put(sf.id, sf.toMap());
          }
        }
      }

      // Eliminar de Hive archivos que ya no existan en Supabase
      if (_filesBox != null && response.isNotEmpty) {
        final keysToRemove = <dynamic>[];
        for (final key in _filesBox!.keys) {
          final val = _filesBox!.get(key);
          if (val is Map) {
            final id = val['id']?.toString();
            if (id != null && !remoteIds.contains(id)) {
              keysToRemove.add(key);
            }
          }
        }
        for (final k in keysToRemove) {
          await _filesBox?.delete(k);
        }
      }

      notifyListeners();
    } catch (e) {
      Logger.warning('Falló sincronización de archivos de estudio: $e', tag: 'StudyFileService');
    }
  }

  /// Escanea Google Drive para detectar borrados externos o archivos nuevos agregados directamente a la carpeta.
  Future<void> syncFromSupabaseAndDrive({Function(String msg)? onNotify}) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    // 1. Sincronización base con Supabase
    await syncFromSupabase();

    try {
      final currentFiles = _allCachedFiles();
      final driveService = GoogleDriveService();

      // 2. Verificar existencia de archivos en Google Drive (Borrados externos).
      //    Los enlaces externos no tienen archivo en Drive, se saltan.
      for (final sf in currentFiles) {
        final driveId = sf.driveFileId;
        if (driveId != null && driveId.isNotEmpty) {
          final existsInDrive = await driveService.checkFileExists(driveId);
          if (!existsInDrive) {
            Logger.info('Archivo "${sf.name}" fue eliminado externamente de Drive.', tag: 'StudyFileService');
            await deleteFile(driveId);
            final subjectName = sf.subject.isNotEmpty ? sf.subject : 'General';
            onNotify?.call('Se eliminó "${sf.name}" de $subjectName');
          }
        }
      }

      // 3. Escanear archivos en carpetas de Drive (Nuevos subidos directamente).
      //    scanBitacoraFolderFiles ignora la subcarpeta de material docente,
      //    porque si no las guías se registrarían además como trabajos.
      final driveFiles = await driveService.scanBitacoraFolderFiles();
      final existingDriveIds = _allCachedFiles()
          .map((f) => f.driveFileId)
          .whereType<String>()
          .toSet();

      for (final df in driveFiles) {
        final driveId = df['drive_file_id'] as String;
        if (!existingDriveIds.contains(driveId)) {
          final newStudyFile = StudyFile(
            name: df['name'],
            subject: df['subject'],
            driveFileId: driveId,
            mimeType: df['mime_type'],
            sizeBytes: df['size_bytes'],
            driveLink: df['drive_link'],
            userId: user.id,
            category: StudyFileCategory.trabajo,
          );
          await saveFile(newStudyFile);
          onNotify?.call('Detectado nuevo archivo en Drive: "${newStudyFile.name}" en ${newStudyFile.subject}');
        }
      }
    } catch (e) {
      Logger.warning('Error en sincronización con Google Drive: $e', tag: 'StudyFileService');
    }

    notifyListeners();
  }
}
