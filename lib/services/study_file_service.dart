import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/study_file_model.dart';
import '../utils/drive_path_classifier.dart';
import '../utils/input_sanitizer.dart';
import '../utils/logger.dart';
import 'career_service.dart';
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
  ///
  /// [propagarADrive] lleva un renombrado también al archivo de Drive. Se
  /// apaga cuando el cambio **viene** de Drive: devolvérselo sería una
  /// llamada inútil que además genera otro evento de modificación, y la
  /// sincronización se quedaría persiguiéndose la cola.
  Future<void> saveFile(StudyFile file, {bool propagarADrive = true}) async {
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
    if (propagarADrive &&
        driveId != null &&
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

  /// Clave donde vive el token de la Changes API de Drive, dentro de la propia
  /// caja de archivos. No es un archivo: las lecturas lo ignoran porque
  /// `getFiles` descarta lo que no sea un mapa con forma de [StudyFile].
  static const String _driveTokenKey = '_drive_page_token';

  /// Pone la app al día con lo que pasó en la carpeta Bitácora de Drive.
  ///
  /// Le pregunta a Drive **qué cambió** desde la última vez (una consulta de
  /// diferencias, no una por archivo) y aplica esos cambios: registra lo que
  /// se subió por fuera de la app, borra lo que se eliminó, y actualiza
  /// nombres y ubicaciones.
  ///
  /// Es lo que reemplaza al barrido anterior, que no podía funcionar: con el
  /// permiso acotado que la app pedía antes, un archivo subido a mano a Drive
  /// era literalmente invisible.
  ///
  /// [completa] recorre la carpeta entera y cuadra los dos lados en vez de
  /// pedir solo las diferencias. Cuesta una consulta por carpeta, así que se
  /// reserva al botón de sincronizar; la automática usa el delta.
  ///
  /// Hace falta porque el delta tiene un punto ciego por diseño: **solo
  /// informa de lo que pasa desde que se pidió el token**. Un archivo que se
  /// borró de Drive antes de eso no aparece en ningún delta, nunca, y su
  /// tarjeta se quedaría en la app para siempre. El barrido completo es la
  /// forma de arreglar cualquier desajuste que se haya acumulado.
  Future<DriveSyncResult> syncDriveChanges({bool completa = false}) async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return const DriveSyncResult.vacio();

    final drive = GoogleDriveService();

    try {
      final guardado = _filesBox?.get(_driveTokenKey)?.toString();

      if (completa || guardado == null || guardado.isEmpty) {
        final arbol = await drive.bitacoraTree(refrescar: true);
        // No encontrar la carpeta Bitácora **no** es "no hay nada nuevo": es
        // no haber podido mirar. Puede que el usuario nunca haya subido nada,
        // pero también que el permiso no alcance o que la carpeta se haya
        // renombrado. Devolver "vacío" acá repetía el error de siempre —
        // anunciar "todo al día" sin haber comprobado nada.
        if (arbol == null) {
          Logger.warning(
            'No se encontró la carpeta Bitácora en Drive: no se sincroniza',
            tag: 'StudyFileService',
          );
          return const DriveSyncResult.sinCarpeta();
        }
        return await _primeraSincronizacion(drive, arbol, user.id);
      }

      final pagina = await drive.listChanges(guardado);
      if (pagina.changes.isEmpty) {
        await _filesBox?.put(_driveTokenKey, pagina.nextStartToken);
        return const DriveSyncResult.vacio();
      }

      // Recorrer el árbol cuesta una consulta por carpeta, así que se reusa el
      // que ya se conoce. Solo se vuelve a recorrer cuando los propios cambios
      // avisan que alguna carpeta se creó, se renombró o se movió — que es
      // justo cuando el árbol quedó viejo.
      //
      // Una carpeta *borrada* no obliga a recorrer: la entrada sobrante en el
      // árbol no hace daño, porque sus archivos vienen en el mismo lote de
      // cambios como ausentes. Y como borrar archivos es lo más frecuente,
      // incluirlo acá haría el recorrido completo casi siempre.
      final carpetasTocadas = pagina.changes.any((c) => c.file?.isFolder == true);
      final arbol = await drive.bitacoraTree(refrescar: carpetasTocadas);
      if (arbol == null) return const DriveSyncResult.vacio();

      final resultado = await _aplicarCambios(pagina.changes, arbol, user.id);

      // El token avanza solo al final y solo si no hubo excepción: si el ciclo
      // se corta a mitad, la próxima vez se reprocesa entero. Es preferible
      // repetir trabajo a que un cambio quede sin aplicar para siempre —que es
      // exactamente el defecto que tenía la versión anterior.
      await _filesBox?.put(_driveTokenKey, pagina.nextStartToken);

      notifyListeners();
      return resultado;
    } on DriveScopeInsufficientException {
      rethrow;
    } catch (e) {
      Logger.warning('Falló la sincronización con Drive: $e',
          tag: 'StudyFileService');
      return const DriveSyncResult.fallo();
    }
  }

  /// Primer recorrido en este dispositivo: cuadra la app con lo que hay hoy en
  /// Drive, y recién entonces empieza a seguir los cambios.
  ///
  /// Los dos sentidos importan, y por motivos distintos:
  ///
  /// - **Registrar lo que falta**, porque la Changes API solo informa de lo que
  ///   pasa *desde* que se pide el token: lo subido antes quedaría invisible.
  /// - **Borrar lo que sobra**, por la misma razón al revés. Un archivo que se
  ///   eliminó de Drive antes de esta primera pasada ya no va a aparecer en
  ///   ningún delta — nunca. Su tarjeta se quedaría en la app para siempre.
  ///   Es exactamente el archivo fantasma que quedó dando vueltas.
  Future<DriveSyncResult> _primeraSincronizacion(
    GoogleDriveService drive,
    BitacoraTree arbol,
    String userId,
  ) async {
    // Si esto lanza, no se toca nada: un listado a medias se leería como
    // "todos estos archivos ya no existen". Ver [GoogleDriveService.listFilesIn].
    final archivos = await drive.listFilesIn(arbol);

    final enDrive = archivos.map((e) => e.id).toSet();
    final conocidos = _driveIdsRegistrados();

    // Deja constancia de lo que se vio realmente. Sin esto, cuando la app y
    // el usuario no coinciden en qué archivos existen, no hay forma de saber
    // cuál de los dos tiene razón.
    Logger.info(
      'Barrido de Drive: ${arbol.paths.length} carpetas, '
      '${archivos.length} archivos en Drive, ${conocidos.length} registrados',
      tag: 'StudyFileService',
    );

    var agregados = 0;
    var ignorados = 0;
    var eliminados = 0;

    for (final entry in archivos) {
      if (conocidos.contains(entry.id)) continue;
      final ruta = arbol.pathOf(entry);
      if (ruta == null) continue;

      if (await _registrar(entry, ruta, userId)) {
        agregados++;
      } else {
        ignorados++;
      }
    }

    // Lo que la app tiene registrado y Drive ya no lista. Solo se miran filas
    // con drive_file_id: los enlaces externos no viven en Drive y no tienen
    // por qué aparecer en ese listado.
    for (final driveId in conocidos.difference(enDrive)) {
      await deleteFile(driveId);
      eliminados++;
      Logger.info(
        'Archivo $driveId ya no está en Drive: se quita de la app',
        tag: 'StudyFileService',
      );
    }

    final token = await drive.getStartPageToken();
    if (token != null && token.isNotEmpty) {
      await _filesBox?.put(_driveTokenKey, token);
    }

    notifyListeners();
    return DriveSyncResult(
      agregados: agregados,
      eliminados: eliminados,
      actualizados: 0,
      ignorados: ignorados,
    );
  }

  /// Aplica los cambios que informó Drive, ignorando todo lo que caiga fuera
  /// del árbol de la carpeta Bitácora.
  Future<DriveSyncResult> _aplicarCambios(
    List<DriveChange> cambios,
    BitacoraTree arbol,
    String userId,
  ) async {
    var agregados = 0;
    var eliminados = 0;
    var actualizados = 0;
    var ignorados = 0;

    for (final cambio in cambios) {
      final existente = _porDriveId(cambio.fileId);

      if (cambio.isGone) {
        // Solo se borra lo que la app ya tenía registrado. Un archivo ajeno
        // que desaparece del Drive del usuario no es asunto de Bitácora.
        if (existente != null) {
          await deleteFile(cambio.fileId);
          eliminados++;
        }
        continue;
      }

      final entry = cambio.file!;
      if (entry.isFolder) continue;

      final ruta = arbol.pathOf(entry);
      if (ruta == null) {
        // Se movió fuera de Bitácora: para la app equivale a que ya no está.
        if (existente != null) {
          await deleteFile(cambio.fileId);
          eliminados++;
        }
        continue;
      }

      if (existente == null) {
        if (await _registrar(entry, ruta, userId)) {
          agregados++;
        } else {
          ignorados++;
        }
        continue;
      }

      if (await _actualizar(existente, entry, ruta)) actualizados++;
    }

    return DriveSyncResult(
      agregados: agregados,
      eliminados: eliminados,
      actualizados: actualizados,
      ignorados: ignorados,
    );
  }

  /// Registra un archivo encontrado en Drive. Devuelve false si su carpeta no
  /// permite deducir carrera y asignatura.
  Future<bool> _registrar(
    DriveEntry entry,
    List<String> ruta,
    String userId,
  ) async {
    final ubicacion =
        classifyDrivePath(ruta, CareerService().getCareers()).location;
    if (ubicacion == null) {
      Logger.info(
        'Archivo "${entry.name}" ignorado: ${ruta.join('/')} no dice carrera y asignatura',
        tag: 'StudyFileService',
      );
      return false;
    }

    await saveFile(
      StudyFile(
        name: entry.name,
        subject: ubicacion.subject,
        careerId: ubicacion.careerId,
        category: ubicacion.category,
        driveFileId: entry.id,
        mimeType: entry.mimeType,
        sizeBytes: entry.sizeBytes,
        driveLink: entry.webViewLink.isNotEmpty
            ? entry.webViewLink
            : 'https://drive.google.com/file/d/${entry.id}/view?usp=sharing',
        userId: userId,
      ),
      propagarADrive: false,
    );
    return true;
  }

  /// Refleja un renombrado o un cambio de carpeta. Devuelve false si nada
  /// cambió, para no anunciar trabajo que no se hizo.
  Future<bool> _actualizar(
    StudyFile actual,
    DriveEntry entry,
    List<String> ruta,
  ) async {
    final ubicacion =
        classifyDrivePath(ruta, CareerService().getCareers()).location;
    if (ubicacion == null) return false;

    final cambio = actual.name != entry.name ||
        actual.subject != ubicacion.subject ||
        actual.careerId != ubicacion.careerId ||
        actual.category != ubicacion.category;
    if (!cambio) return false;

    await saveFile(
      actual.copyWith(
        name: entry.name,
        subject: ubicacion.subject,
        careerId: ubicacion.careerId,
        category: ubicacion.category,
      ),
      propagarADrive: false,
    );
    return true;
  }

  /// El archivo en caché que corresponde a [driveId], si lo hay.
  StudyFile? _porDriveId(String driveId) {
    if (_filesBox == null || driveId.isEmpty) return null;
    for (final raw in _filesBox!.values) {
      if (raw is Map && raw['drive_file_id'] == driveId) {
        return StudyFile.fromMap(Map<String, dynamic>.from(raw));
      }
    }
    return null;
  }

  /// Ids de Drive que la app ya tiene registrados para el usuario actual.
  ///
  /// El filtro por usuario importa acá más que en ningún otro lado: este
  /// conjunto alimenta un borrado, y el Drive que se consulta es el de la
  /// sesión abierta. Una fila de otra cuenta se leería como "no está en Drive".
  Set<String> _driveIdsRegistrados() {
    final box = _filesBox;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (box == null || userId == null) return {};

    return box.values
        .whereType<Map>()
        .where((m) => m['user_id'] == userId)
        .map((m) => m['drive_file_id']?.toString())
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();
  }
}

/// Qué hizo una pasada de [StudyFileService.syncDriveChanges].
class DriveSyncResult {
  final int agregados;
  final int eliminados;
  final int actualizados;

  /// Archivos que están en la carpeta Bitácora pero en un lugar del que no se
  /// puede deducir carrera y asignatura. No se registran, y se cuentan para
  /// poder decirlo: desaparecer en silencio es lo que hace que alguien crea
  /// que la app perdió su archivo.
  final int ignorados;

  const DriveSyncResult({
    required this.agregados,
    required this.eliminados,
    required this.actualizados,
    required this.ignorados,
  });

  const DriveSyncResult.vacio()
      : agregados = 0,
        eliminados = 0,
        actualizados = 0,
        ignorados = 0;

  /// No se pudo consultar a Drive. Se distingue de [DriveSyncResult.vacio]
  /// para no anunciar "todo al día" cuando en realidad no se comprobó nada:
  /// esa confusión exacta es la que hacía que el botón anterior mintiera.
  const DriveSyncResult.fallo()
      : agregados = -1,
        eliminados = 0,
        actualizados = 0,
        ignorados = 0;

  /// Drive respondió, pero no hay carpeta "Bitácora" que mirar. Tampoco es
  /// "todo al día": o nunca se subió nada, o la carpeta se renombró o movió.
  const DriveSyncResult.sinCarpeta()
      : agregados = -2,
        eliminados = 0,
        actualizados = 0,
        ignorados = 0;

  bool get fallo => agregados == -1;
  bool get sinCarpeta => agregados == -2;
  bool get sinCambios =>
      agregados == 0 && eliminados == 0 && actualizados == 0;

  /// Frase para mostrarle al usuario.
  String get resumen {
    if (fallo) return 'No se pudo consultar Google Drive';
    if (sinCarpeta) {
      return 'No se encontró la carpeta "Bitácora" en tu Google Drive';
    }

    final partes = <String>[
      if (agregados == 1) '1 archivo nuevo' else if (agregados > 1) '$agregados archivos nuevos',
      if (eliminados == 1) '1 eliminado' else if (eliminados > 1) '$eliminados eliminados',
      if (actualizados == 1) '1 actualizado' else if (actualizados > 1) '$actualizados actualizados',
    ];

    final aviso = ignorados == 0
        ? ''
        : ignorados == 1
            ? '. 1 archivo está en una carpeta sin carrera o asignatura'
            : '. $ignorados archivos están en carpetas sin carrera o asignatura';

    if (partes.isEmpty) return 'Todo al día con Google Drive$aviso';
    return 'Drive: ${partes.join(', ')}$aviso';
  }
}
