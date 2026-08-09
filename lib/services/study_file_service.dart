import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/study_file_model.dart';
import '../utils/input_sanitizer.dart';
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
  /// Valor de [StudyFile.careerId] que representa "sin carrera" en el filtro.
  static const String noCareerFilter = '__sin_carrera__';

  List<StudyFile> getFiles({
    String category = StudyFileCategory.trabajo,
    String? careerId,
  }) {
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
          .where((f) {
            if (careerId == null) return true;
            final id = f.careerId;
            if (careerId == noCareerFilter) return id == null || id.isEmpty;
            return id == careerId;
          })
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (e) {
      Logger.error('Error parseando archivos de estudio: $e', tag: 'StudyFileService');
      return [];
    }
  }

  /// Carreras que aparecen entre los archivos de [category], para armar el
  /// filtro sin ofrecer opciones que no seleccionarían nada.
  Set<String> usedCareerIds(String category) =>
      getFiles(category: category)
          .map((f) => (f.careerId == null || f.careerId!.isEmpty)
              ? noCareerFilter
              : f.careerId!)
          .toSet();

  /// Único punto de guardado de archivos (subida, edición y enlaces): a
  /// diferencia de tareas y reuniones, que sanitizan en la pantalla, acá se
  /// hace en el servicio para que cubra los tres flujos sin repetir la
  /// llamada en cada uno.
  Future<void> saveFile(StudyFile file) async {
    final user = Supabase.instance.client.auth.currentUser;
    final fileId = file.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    final sanitizedName = InputSanitizer.sanitizeText(
      file.name,
      maxLength: InputSanitizer.maxTitleLength,
    );
    final fileToSave = StudyFile.fromMap({
      ...file.toMap(),
      'id': fileId,
      // Un nombre que quede vacío tras sanitizar (era solo HTML/scripts)
      // rompería la lista y las tarjetas, que asumen texto no vacío.
      'name': sanitizedName.isEmpty ? file.name.trim() : sanitizedName,
      if (file.description != null)
        'description': InputSanitizer.sanitizeText(file.description!),
    });

    // Si el servidor no lo acepta —sin red, o rechazado— queda marcado para
    // reintentarlo en la próxima sincronización. Ver [_pendingKey].
    var pendiente = user == null;
    if (user != null) {
      try {
        final payload = fileToSave.toMap();
        payload['user_id'] = user.id;

        await Supabase.instance.client
            .from('study_files')
            .upsert(payload, onConflict: 'id');
      } catch (e) {
        pendiente = true;
        Logger.error('Error guardando metadato de archivo en Supabase: $e', error: e, tag: 'StudyFileService');
      }
    }

    // Si el nombre cambió, llevarlo también a Drive: si no, el archivo queda
    // llamándose distinto en cada lado. Es best-effort a propósito — que
    // falle la red no debe impedir guardar el cambio en la app.
    final driveId = fileToSave.driveFileId;
    final nombreAnterior = _cachedNameOf(fileId);
    if (driveId != null &&
        driveId.isNotEmpty &&
        nombreAnterior != null &&
        nombreAnterior != fileToSave.name) {
      await GoogleDriveService().renameFile(driveId, fileToSave.name);
    }

    await _filesBox?.put(fileId, {
      ...fileToSave.toMap(),
      if (pendiente) _pendingKey: true,
    });
    notifyListeners();
  }

  /// Marca, dentro del mapa guardado en Hive, de que esta fila todavía no
  /// llegó a Supabase.
  ///
  /// No es parte de [StudyFile]: `fromMap` la ignora, así que solo existe en
  /// la caché. Sirve para subir en la sincronización **únicamente** lo que
  /// falta, en vez de reenviar todo.
  static const String _pendingKey = '_pending';

  /// Archivos guardados localmente que nunca llegaron al servidor.
  List<StudyFile> _pendingFiles() {
    if (_filesBox == null) return [];
    return _filesBox!.values
        .whereType<Map>()
        .where((m) => m[_pendingKey] == true)
        .map((m) => StudyFile.fromMap(Map<String, dynamic>.from(m)))
        .toList();
  }

  /// Nombre con el que estaba guardado [fileId], o null si es nuevo.
  String? _cachedNameOf(String fileId) {
    final raw = _filesBox?.get(fileId);
    if (raw is Map) return raw['name']?.toString();
    return null;
  }

  /// Vacía la caché local de archivos. Se llama al cerrar sesión: la caja de
  /// Hive sobrevive al logout, y si queda con los archivos de la cuenta
  /// anterior, la siguiente los ve y —peor— el escaneo de Drive los da por
  /// borrados porque no están en el Drive de la cuenta nueva.
  Future<void> clearCache() async {
    await _filesBox?.clear();
    notifyListeners();
  }

  /// Borra el archivo en todas partes: Google Drive, Supabase y la caché.
  ///
  /// Devuelve false si el archivo de Drive no se pudo borrar. Antes esto vivía
  /// en la pantalla y solo lo hacía la pestaña de archivos: borrar material
  /// docente quitaba la tarjeta y dejaba el archivo en Drive para siempre. Y
  /// el resultado no se miraba, así que un fallo se anunciaba igual como
  /// "archivo eliminado".
  Future<bool> deleteStudyFile(StudyFile file) async {
    var driveOk = true;

    final driveId = file.driveFileId;
    if (driveId != null && driveId.isNotEmpty) {
      driveOk = await GoogleDriveService().deleteFile(driveId);
      if (!driveOk) {
        Logger.warning(
          'No se pudo borrar "${file.name}" de Google Drive',
          tag: 'StudyFileService',
        );
      }
      await deleteFile(driveId);
    }

    final id = file.id;
    if (id != null && id.isNotEmpty) await deleteFile(id);

    return driveOk;
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
      // 1. Subir SOLO lo que nunca llegó al servidor.
      //
      // Antes se reenviaba la caché entera en cada sincronización, y eso
      // resucitaba lo borrado: si eliminabas un archivo en el teléfono,
      // desaparecía de Supabase, pero la caché del navegador todavía lo tenía
      // y en su siguiente sincronización lo volvía a insertar — y de ahí
      // regresaba al teléfono. El servidor manda; la caché solo aporta lo que
      // se creó sin conexión.
      for (final f in _pendingFiles()) {
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

      // Eliminar de Hive archivos que ya no existan en Supabase.
      //
      // Sin condicionar a que la respuesta traiga algo: antes esto se saltaba
      // cuando la cuenta no tenía ningún archivo, que es justo el caso en que
      // la caché quedaba llena de los archivos de la sesión anterior.
      if (_filesBox != null) {
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

  /// Antes existía `syncFromSupabaseAndDrive`, que contrastaba la caché con
  /// las carpetas de Drive. Se eliminó por dos motivos:
  ///
  /// 1. **Detectar archivos nuevos era imposible.** La app pide el ámbito
  ///    OAuth `drive.file`, que da acceso solo a los archivos que ella misma
  ///    creó. Un archivo que el usuario arrastra a Drive desde el computador
  ///    no aparece en ningún listado, por bien escrito que esté el escaneo.
  ///    Subir a `drive.readonly` exigiría verificación con auditoría de
  ///    Google, y para esta app no compensa.
  ///
  /// 2. **Detectar borrados externos era peligroso.** El barrido llamaba a
  ///    `deleteFile()`, que borra también de Supabase. Un token a medias o un
  ///    404 pasajero se traducía en pérdida de datos del servidor, sin vuelta
  ///    atrás, por un problema de red.
  ///
  /// Ahora el borrado es simétrico —eliminar en la app elimina en Drive, ver
  /// [deleteStudyFile]— así que las dos copias no divergen por el uso normal.
  /// Si alguien borra un archivo directamente en Drive, su tarjeta queda en la
  /// app hasta que la elimine: molesto, pero reversible, que es justo lo que
  /// no era el comportamiento anterior.
}
