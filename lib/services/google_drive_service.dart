import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/logger.dart';
import '../utils/drive_token_stub.dart'
    if (dart.library.html) '../utils/drive_token_web.dart';

// Google OAuth Client ID (mismo que está en web/index.html)
const _googleClientId =
    '651071616802-1pgjc8uu88a58m5999noa0uits5n6s1j.apps.googleusercontent.com';

class _DriveAuthExpiredException implements Exception {}

/// El token sirve, pero no alcanza para lo que se pidió.
///
/// Pasa si el scope concedido cambió y el token que se tenía guardado es del
/// scope anterior: sigue vigente, así que Drive responde 403
/// `insufficientPermissions` en vez de 401. Reintentar con un token nuevo no
/// arregla nada — hay que volver a pedir el consentimiento.
class DriveScopeInsufficientException implements Exception {
  const DriveScopeInsufficientException();

  @override
  String toString() =>
      'Bitácora necesita que vuelvas a autorizar el acceso a Google Drive.';
}

/// Haría falta pedirle permiso al usuario, y no es momento de interrumpirlo.
///
/// La ventana de permisos de Google muestra —mientras la app no esté
/// verificada— una pantalla que dice "esta app no es segura". Abrirla sola, al
/// arrancar la app o al volver a ella, es alarmante y además la bloquean los
/// navegadores, porque no viene de un clic. Esta excepción marca ese caso para
/// que la sincronización automática se rinda en silencio y espere a que el
/// usuario lo pida.
class DriveNeedsConsentException implements Exception {
  const DriveNeedsConsentException();

  @override
  String toString() => 'Falta autorizar el acceso a Google Drive.';
}

// Algunos llamadores pasan solo la extensión del archivo (p. ej. "pdf")
// en vez de un MIME type real, porque file_picker no expone el MIME type
// en todas las plataformas. Google Drive rechaza con 400 un mimeType que
// no tenga forma "tipo/subtipo", así que esto normaliza ambos casos.
const _extensionMimeTypes = <String, String>{
  'pdf': 'application/pdf',
  'doc': 'application/msword',
  'docx':
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'xls': 'application/vnd.ms-excel',
  'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'ppt': 'application/vnd.ms-powerpoint',
  'pptx':
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'txt': 'text/plain',
  'csv': 'text/csv',
  'rtf': 'application/rtf',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'gif': 'image/gif',
  'webp': 'image/webp',
  'svg': 'image/svg+xml',
  'zip': 'application/zip',
  'rar': 'application/vnd.rar',
  '7z': 'application/x-7z-compressed',
  'mp4': 'video/mp4',
  'mp3': 'audio/mpeg',
  'json': 'application/json',
  'xml': 'application/xml',
  'html': 'text/html',
  'htm': 'text/html',
};

/// Normaliza un nombre de carpeta para compararlo: minúsculas, sin tildes y
/// sin espacios de sobra.
///
/// Hace falta porque el nombre de la carpeta lo escribe una persona y el de
/// la carrera viene de la base: "Teologia" en Drive y "Teología" en la app son
/// la misma cosa, y sin esto la app crearía una carpeta duplicada al lado.
String normalizeFolderName(String value) {
  const acentos = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
    'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
    'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
    'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
    'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
    'ñ': 'n', 'ç': 'c',
  };
  final lower = value.trim().toLowerCase();
  final buffer = StringBuffer();
  for (final ch in lower.split('')) {
    buffer.write(acentos[ch] ?? ch);
  }
  return buffer.toString();
}

String _resolveMimeType(String mimeType) {
  final trimmed = mimeType.trim();
  if (trimmed.contains('/')) return trimmed;
  final ext = trimmed.toLowerCase().replaceFirst('.', '');
  return _extensionMimeTypes[ext] ?? 'application/octet-stream';
}

class DriveUploadResult {
  final String fileId;
  final String webViewLink;
  final bool isStoredInGoogleDrive;

  DriveUploadResult({
    required this.fileId,
    required this.webViewLink,
    required this.isStoredInGoogleDrive,
  });
}

/// Un archivo o carpeta de Drive, con lo mínimo para registrarlo o ubicarlo.
class DriveEntry {
  final String id;
  final String name;
  final List<String> parents;
  final String? mimeType;
  final int? sizeBytes;
  final String webViewLink;
  final bool trashed;

  const DriveEntry({
    required this.id,
    required this.name,
    required this.parents,
    this.mimeType,
    this.sizeBytes,
    this.webViewLink = '',
    this.trashed = false,
  });

  static const String folderMimeType = 'application/vnd.google-apps.folder';
  bool get isFolder => mimeType == folderMimeType;

  /// Carpeta que lo contiene, o null si Drive no la informó.
  String? get parentId => parents.isEmpty ? null : parents.first;

  factory DriveEntry.fromJson(Map<String, dynamic> json) => DriveEntry(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        parents: (json['parents'] as List?)
                ?.map((p) => p.toString())
                .toList(growable: false) ??
            const [],
        mimeType: json['mimeType']?.toString(),
        sizeBytes: int.tryParse(json['size']?.toString() ?? ''),
        webViewLink: json['webViewLink']?.toString() ?? '',
        trashed: json['trashed'] == true,
      );
}

/// Un cambio informado por la Changes API de Drive.
class DriveChange {
  final String fileId;

  /// Drive lo dio de baja: borrado definitivo, o el usuario perdió acceso.
  final bool removed;

  /// Estado actual del archivo. Null cuando [removed] es true.
  final DriveEntry? file;

  const DriveChange({
    required this.fileId,
    required this.removed,
    this.file,
  });

  /// Si el archivo ya no debe aparecer en la app. La papelera cuenta: el
  /// usuario ya lo dio por borrado, aunque el enlace le siga funcionando por
  /// ser el dueño.
  bool get isGone => removed || file == null || file!.trashed;

  factory DriveChange.fromJson(Map<String, dynamic> json) {
    final rawFile = json['file'];
    return DriveChange(
      fileId: json['fileId']?.toString() ?? '',
      removed: json['removed'] == true,
      file: rawFile is Map
          ? DriveEntry.fromJson(Map<String, dynamic>.from(rawFile))
          : null,
    );
  }
}

/// Lo que devuelve una pasada completa de la Changes API.
class DriveChangesPage {
  final List<DriveChange> changes;

  /// Token con el que empezar la próxima consulta. Se guarda **solo** si el
  /// ciclo entero terminó bien: si se guardara antes, un fallo a mitad dejaría
  /// cambios sin procesar que ya nadie volvería a mirar.
  final String nextStartToken;

  const DriveChangesPage({
    required this.changes,
    required this.nextStartToken,
  });
}

/// El árbol de carpetas de Bitácora, con la ruta de cada una.
///
/// Con el permiso acotado (`drive.file`) Google ya solo deja ver lo que la
/// app creó, pero esto se conserva como segunda barrera: si algún día
/// cambiara el scope, o algo quedara accesible por otra vía, la restricción a
/// la carpeta Bitácora no depende únicamente de lo que Google decida permitir.
class BitacoraTree {
  final String rootId;

  /// Id de carpeta → ruta relativa a la raíz. La raíz misma es lista vacía.
  final Map<String, List<String>> paths;

  const BitacoraTree({required this.rootId, required this.paths});

  /// Si [folderId] es la carpeta Bitácora o alguna de sus descendientes.
  bool containsFolder(String? folderId) =>
      folderId != null && paths.containsKey(folderId);

  /// Si [entry] vive dentro del árbol. Un archivo sin `parents` informados no
  /// cuenta: sin saber dónde está, no se puede afirmar que sea nuestro.
  bool containsEntry(DriveEntry entry) =>
      entry.parents.any(containsFolder);

  /// Ruta de carpetas de [entry] relativa a la raíz, o null si está fuera.
  List<String>? pathOf(DriveEntry entry) {
    for (final parent in entry.parents) {
      final ruta = paths[parent];
      if (ruta != null) return ruta;
    }
    return null;
  }
}

class GoogleDriveService {
  static final GoogleDriveService _instance = GoogleDriveService._internal();
  factory GoogleDriveService() => _instance;
  GoogleDriveService._internal();

  static const _tokenKey = 'google_drive_access_token';

  /// Subcarpeta donde va el material docente, dentro de la carpeta de cada
  /// asignatura. Mantiene el Drive del estudiante ordenado igual que la app:
  /// carrera, asignatura, y las guías aparte de los trabajos.
  static const String teachingMaterialFolderName = 'Material docente';

  // El token de acceso a Drive se guarda cifrado (Keystore/Keychain vía
  // flutter_secure_storage), igual que la clave de cifrado de Hive — antes
  // se guardaba en texto plano con SharedPreferences.
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Token de Drive **en web**, y solo en memoria.
  ///
  /// En web `flutter_secure_storage` no tiene Keystore ni Keychain detrás: cae
  /// a almacenamiento del navegador, o sea que el token de Google quedaba
  /// escrito en el disco del equipo, legible por cualquiera con acceso a ese
  /// perfil y sobreviviendo al cierre de la pestaña.
  ///
  /// El costo de no persistirlo es pequeño: Supabase ya devuelve un
  /// `providerToken` con la sesión, y si no lo hay, GIS abre un popup. El
  /// token muere al recargar la página, que es exactamente lo que se quiere en
  /// un computador compartido.
  static String? _webToken;

  /// Guarda el token para reusarlo. En web solo en memoria (ver [_webToken]).
  static Future<void> persistToken(String token) async {
    if (token.isEmpty) return;

    if (kIsWeb) {
      _webToken = token;
      return;
    }

    await _secureStorage.write(key: _tokenKey, value: token);
    Logger.info('Token de Drive guardado de forma segura.', tag: 'GoogleDriveService');
  }

  /// Limpia el token al cerrar sesión.
  static Future<void> clearToken() async {
    _webToken = null;
    if (kIsWeb) return;
    await _secureStorage.delete(key: _tokenKey);
  }

  /// Obtiene el token disponible. Orden de prioridad:
  /// 1. Sesión activa de Supabase (providerToken)
  /// 2. Token ya obtenido antes (memoria en web, llavero del sistema si no)
  Future<String?> get _storedToken async {
    final sessionToken =
        Supabase.instance.client.auth.currentSession?.providerToken;
    if (sessionToken != null && sessionToken.isNotEmpty) {
      await persistToken(sessionToken);
      return sessionToken;
    }
    if (kIsWeb) return _webToken;
    return _secureStorage.read(key: _tokenKey);
  }

  /// Obtiene el token de Drive.
  ///
  /// En Web: reutiliza el token guardado y, si no hay ninguno, abre un
  /// popup de Google Identity Services (GIS) para solicitarlo.
  ///
  /// En móvil/desktop: los access token de Google expiran cada ~1 hora, así
  /// que en vez de confiar en el último token guardado (que puede estar
  /// vencido) se pide uno fresco de forma silenciosa en cada uso, usando la
  /// sesión nativa de Google ya autorizada — igual que hacen apps como
  /// WhatsApp: el usuario da el permiso una sola vez y la app lo renueva
  /// sola, sin volver a mostrar ningún diálogo.
  Future<String?> getOrRequestToken() async {
    if (!kIsWeb) {
      final freshToken = await requestDriveTokenPlatform(_googleClientId);
      if (freshToken != null && freshToken.isNotEmpty) {
        await persistToken(freshToken);
        return freshToken;
      }
      // Sin red u otro fallo silencioso (p. ej. el usuario revocó el
      // acceso): usar el último token conocido como último recurso.
      return _storedToken;
    }

    String? token = await _storedToken;
    if (token != null && token.isNotEmpty) return token;

    // No hay token → pedir via popup GIS (solo funciona en Web)
    Logger.info(
      'Token de Drive no encontrado. Solicitando via GIS popup...',
      tag: 'GoogleDriveService',
    );
    token = await requestDriveTokenPlatform(_googleClientId);
    if (token != null && token.isNotEmpty) {
      await persistToken(token);
    }
    return token;
  }

  /// El token que ya se tenga, **sin abrir ninguna ventana de permisos**.
  ///
  /// Existe para separar dos cosas que no son lo mismo: usar un permiso ya
  /// concedido, y pedirlo. Pedirlo abre un popup de Google que, mientras la
  /// app no esté verificada, muestra una pantalla de advertencia. Eso solo
  /// puede pasar cuando el usuario hizo algo para provocarlo — nunca al abrir
  /// la app ni al volver a ella, que es cuando más asusta y menos se entiende.
  Future<String?> tokenSilencioso() async {
    if (kIsWeb) return _storedToken;
    // En móvil renovar es de verdad silencioso: la sesión nativa de Google ya
    // está autorizada y no se muestra ningún diálogo.
    return getOrRequestToken();
  }

  /// Pide un token nuevo saltándose el cache (Supabase providerToken /
  /// storage), a diferencia de [getOrRequestToken]. Se usa al reintentar
  /// tras un 401: en Web, el providerToken de Supabase no se refresca solo,
  /// así que reusar [getOrRequestToken] devolvería el mismo token vencido.
  ///
  /// [forceConsent] además vuelve a mostrar la pantalla de permisos de Google.
  /// Sin eso, quien autorizó la app cuando pedía `drive.file` recibe una y
  /// otra vez un token con ese scope viejo: es válido, así que Drive no
  /// responde 401 sino 403, y reintentar sin forzar el consentimiento no
  /// cambia nada.
  Future<String?> _requestFreshToken({bool forceConsent = false}) async {
    final token = await requestDriveTokenPlatform(
      _googleClientId,
      forceConsent: forceConsent,
    );
    if (token != null && token.isNotEmpty) {
      await persistToken(token);
      return token;
    }
    return null;
  }

  /// Traduce una respuesta de la API de Drive a la excepción que corresponde.
  ///
  /// Existe porque el 403 se venía tratando como "no se pudo, mala suerte", y
  /// ese es justo el caso que hay que distinguir: `insufficientPermissions`
  /// significa que el usuario tiene que volver a dar permiso, no que haya
  /// fallado la red. Confundir un fallo de autorización con "sin novedad" es
  /// lo que hacía que la app dijera "todo al día" sin haber comprobado nada.
  void _throwIfAuthProblem(http.Response response) {
    if (response.statusCode == 401) throw _DriveAuthExpiredException();
    if (response.statusCode == 403 &&
        response.body.contains('insufficientPermissions')) {
      throw const DriveScopeInsufficientException();
    }
  }

  /// Ejecuta [peticion] con un token válido, reintentando una vez si Drive
  /// dice que el token venció (401) o que no alcanza (403).
  ///
  /// Es el mismo patrón que ya usaba la subida de archivos, ahora disponible
  /// para el resto de las llamadas: antes cada una lo resolvía a su manera —o
  /// no lo resolvía— y un token vencido se convertía en silencio en "no hay
  /// nada que informar".
  /// [interactivo] decide si se puede abrir una ventana de permisos. En false
  /// —sincronización automática— la petición se abandona antes que molestar:
  /// lanza [DriveNeedsConsentException] y quien llama lo trata como "todavía
  /// no", no como un error.
  Future<T> _withToken<T>(
    Future<T> Function(String token) peticion, {
    bool interactivo = true,
  }) async {
    final token =
        interactivo ? await getOrRequestToken() : await tokenSilencioso();
    if (token == null || token.isEmpty) {
      if (!interactivo) throw const DriveNeedsConsentException();
      throw Exception('No se pudo obtener acceso a Google Drive.');
    }

    try {
      return await peticion(token);
    } on _DriveAuthExpiredException {
      await clearToken();
      if (!interactivo) throw const DriveNeedsConsentException();
      final fresco = await _requestFreshToken();
      if (fresco == null || fresco.isEmpty) {
        throw Exception('El acceso a Google Drive expiró.');
      }
      return await peticion(fresco);
    } on DriveScopeInsufficientException {
      await clearToken();
      if (!interactivo) throw const DriveNeedsConsentException();
      final ampliado = await _requestFreshToken(forceConsent: true);
      if (ampliado == null || ampliado.isEmpty) rethrow;
      return await peticion(ampliado);
    }
  }

  /// Sube el archivo al Google Drive del usuario.
  /// Si se especifica [subject], el archivo se guardará dentro de una carpeta con el nombre
  /// de la asignatura (creándola si no existe) dentro de la carpeta "Bitácora".
  ///
  /// Usa subida "resumable" (en un solo request) en vez de "multipart": la
  /// API de Drive solo garantiza multipart para archivos de hasta 5MB, y
  /// esta app permite archivos de hasta 50MB.
  Future<DriveUploadResult> uploadStudyFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? career,
    String? subject,
    String? subfolder,
  }) async {
    final token = await getOrRequestToken();

    if (token == null || token.isEmpty) {
      throw Exception(
        'No se pudo obtener acceso a Google Drive. '
        'Por favor acepta los permisos en el popup de Google.',
      );
    }

    Logger.info(
      'Subiendo "$fileName" al Google Drive del usuario (${subject ?? "Sin asignatura"})...',
      tag: 'GoogleDriveService',
    );

    try {
      return await _uploadWithToken(
        token,
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
        career: career,
        subject: subject,
        subfolder: subfolder,
      );
    } on _DriveAuthExpiredException {
      // El token venció justo antes/durante la subida: pedir uno nuevo
      // (renovación silenciosa en móvil, sin pedirle nada al usuario) y
      // reintentar una única vez antes de rendirse.
      await clearToken();
      final freshToken = await _requestFreshToken();
      if (freshToken == null || freshToken.isEmpty) {
        throw Exception(
          'El acceso a Google Drive expiró. Intenta subir el archivo nuevamente.',
        );
      }
      return await _uploadWithToken(
        freshToken,
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
        career: career,
        subject: subject,
        subfolder: subfolder,
      );
    }
  }

  Future<DriveUploadResult> _uploadWithToken(
    String token, {
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? career,
    String? subject,
    String? subfolder,
  }) async {
    final folderId = await _getOrCreateSubjectFolder(token, subject,
        career: career, subfolder: subfolder);
    final effectiveMimeType = _resolveMimeType(mimeType);

    final metadata = {
      'name': fileName,
      'mimeType': effectiveMimeType,
      'description': 'Archivo de estudio — Bitácora App',
      if (folderId != null) 'parents': [folderId],
    };

    // 1. Abrir sesión de subida resumable.
    final initResponse = await http.post(
      Uri.parse(
        'https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable',
      ),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json; charset=UTF-8',
        'X-Upload-Content-Type': effectiveMimeType,
        'X-Upload-Content-Length': '${bytes.length}',
      },
      body: jsonEncode(metadata),
    );

    if (initResponse.statusCode == 401) {
      throw _DriveAuthExpiredException();
    }
    if (initResponse.statusCode != 200) {
      Logger.error(
        'Google Drive API error al iniciar subida ${initResponse.statusCode}: ${initResponse.body}',
        tag: 'GoogleDriveService',
      );
      throw Exception(
        'Error al iniciar la subida a Google Drive (${initResponse.statusCode}).',
      );
    }

    final uploadUri = initResponse.headers['location'];
    if (uploadUri == null) {
      throw Exception('Google Drive no devolvió una URL de subida.');
    }

    // 2. Enviar los bytes del archivo completos en un único PUT.
    final uploadResponse = await http.put(
      Uri.parse(uploadUri),
      headers: {
        'Content-Type': effectiveMimeType,
        'Content-Length': '${bytes.length}',
      },
      body: bytes,
    );

    if (uploadResponse.statusCode == 200 || uploadResponse.statusCode == 201) {
      final data = jsonDecode(uploadResponse.body) as Map<String, dynamic>;
      final fileId = data['id'] as String;
      final driveLink =
          'https://drive.google.com/file/d/$fileId/view?usp=sharing';
      Logger.info(
        'Archivo subido a Google Drive. ID: $fileId',
        tag: 'GoogleDriveService',
      );
      return DriveUploadResult(
        fileId: fileId,
        webViewLink: driveLink,
        isStoredInGoogleDrive: true,
      );
    } else if (uploadResponse.statusCode == 401) {
      throw _DriveAuthExpiredException();
    } else {
      Logger.error(
        'Google Drive API error ${uploadResponse.statusCode}: ${uploadResponse.body}',
        tag: 'GoogleDriveService',
      );
      throw Exception(
        'Error al subir a Google Drive (${uploadResponse.statusCode}).',
      );
    }
  }

  /// Renombra el archivo en Drive para que coincida con el nombre de la app.
  ///
  /// Sin esto el archivo quedaba con un nombre en Bitácora y otro en Drive,
  /// para siempre: `saveFile()` solo escribía en Supabase y en Hive. Los
  /// enlaces no dependen del nombre, así que era confuso, no roto.
  ///
  /// Best-effort: si falla, el renombrado local se conserva igual.
  Future<bool> renameFile(String fileId, String newName) async {
    if (fileId.isEmpty || fileId.contains('/') || newName.trim().isEmpty) {
      return false;
    }
    if (!await belongsToBitacora(fileId)) {
      Logger.warning(
        'No se renombra $fileId: está fuera de la carpeta Bitácora',
        tag: 'GoogleDriveService',
      );
      return false;
    }
    final token = await getOrRequestToken();
    if (token == null || token.isEmpty) return false;

    try {
      final response = await http.patch(
        Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'name': newName.trim()}),
      );
      if (response.statusCode == 200) return true;
      Logger.warning(
        'No se pudo renombrar $fileId en Drive (${response.statusCode})',
        tag: 'GoogleDriveService',
      );
    } catch (e) {
      Logger.warning('Error renombrando $fileId en Drive: $e',
          tag: 'GoogleDriveService');
    }
    return false;
  }

  /// Campos que se piden de cada archivo. Lo justo para registrarlo y ubicarlo.
  static const String _entryFields =
      'id,name,parents,mimeType,size,webViewLink,trashed';

  /// Marca el punto de partida: "quiero saber los cambios de aquí en adelante".
  ///
  /// Se pide una sola vez por dispositivo; después el token lo va renovando
  /// cada llamada a [listChanges].
  Future<String?> getStartPageToken({bool interactivo = true}) =>
      _withToken(interactivo: interactivo, (token) async {
        final response = await http.get(
          Uri.parse(
            'https://www.googleapis.com/drive/v3/changes/startPageToken',
          ),
          headers: {'Authorization': 'Bearer $token'},
        );
        _throwIfAuthProblem(response);
        if (response.statusCode != 200) {
          Logger.warning(
            'No se pudo obtener el token de cambios de Drive (${response.statusCode})',
            tag: 'GoogleDriveService',
          );
          return null;
        }
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['startPageToken']?.toString();
      });

  /// Qué cambió en el Drive del usuario desde [pageToken].
  ///
  /// Una sola consulta de diferencias, no una por archivo: cubre agregados,
  /// borrados, renombrados y movimientos a la vez, y es lo que permite que la
  /// app se entere de lo que se hizo directamente en Drive. Es el mecanismo
  /// que Google ofrece justo para esto.
  Future<DriveChangesPage> listChanges(String pageToken,
          {bool interactivo = true}) =>
      _withToken(interactivo: interactivo, (token) async {
        final cambios = <DriveChange>[];
        var actual = pageToken;
        String? siguienteInicio;

        // Drive pagina: se sigue mientras entregue nextPageToken, y la última
        // página trae el token con el que empezar la próxima vez.
        while (true) {
          final uri = Uri.parse(
            'https://www.googleapis.com/drive/v3/changes'
            '?pageToken=$actual'
            '&pageSize=200'
            '&fields=${Uri.encodeComponent('nextPageToken,newStartPageToken,changes(fileId,removed,file($_entryFields))')}',
          );
          final response =
              await http.get(uri, headers: {'Authorization': 'Bearer $token'});
          _throwIfAuthProblem(response);
          if (response.statusCode != 200) {
            throw Exception(
              'Drive respondió ${response.statusCode} al pedir los cambios.',
            );
          }

          final data = jsonDecode(response.body) as Map<String, dynamic>;
          for (final raw in (data['changes'] as List?) ?? const []) {
            if (raw is Map) {
              cambios.add(DriveChange.fromJson(Map<String, dynamic>.from(raw)));
            }
          }

          final siguientePagina = data['nextPageToken']?.toString();
          if (siguientePagina != null && siguientePagina.isNotEmpty) {
            actual = siguientePagina;
            continue;
          }
          siguienteInicio = data['newStartPageToken']?.toString();
          break;
        }

        return DriveChangesPage(
          changes: cambios,
          // Si Drive no devolvió uno nuevo, se conserva el que había: perder
          // el token obligaría a rehacer el barrido completo.
          nextStartToken: (siguienteInicio != null && siguienteInicio.isNotEmpty)
              ? siguienteInicio
              : pageToken,
        );
      });

  /// Recorre las carpetas de Bitácora y devuelve el árbol con sus rutas.
  ///
  /// Devuelve null si la carpeta Bitácora todavía no existe — no se crea acá:
  /// sincronizar es una lectura, y crear carpetas en el Drive de alguien que
  /// nunca subió nada sería ensuciar por adelantado.
  Future<BitacoraTree?> loadBitacoraTree({bool interactivo = true}) =>
      _withToken(interactivo: interactivo, (token) async {
        final rootId = await _findBitacoraFolder(token);
        if (rootId == null) return null;

        final paths = <String, List<String>>{rootId: const []};
        final pendientes = <String>[rootId];

        while (pendientes.isNotEmpty) {
          final actual = pendientes.removeAt(0);
          final rutaActual = paths[actual]!;

          for (final carpeta in await _listChildren(token, actual,
              soloCarpetas: true)) {
            if (paths.containsKey(carpeta.id)) continue;
            paths[carpeta.id] = [...rutaActual, carpeta.name];
            pendientes.add(carpeta.id);
          }
        }

        return BitacoraTree(rootId: rootId, paths: paths);
      });

  /// Todos los archivos (no carpetas) que hay dentro del árbol de [tree].
  ///
  /// Es el barrido inicial: corre una sola vez, cuando el dispositivo empieza
  /// a seguir los cambios, para registrar lo que ya estaba en Drive antes.
  /// A partir de ahí manda [listChanges], que es mucho más barato.
  Future<List<DriveEntry>> listFilesIn(BitacoraTree tree,
          {bool interactivo = true}) =>
      _withToken(interactivo: interactivo, (token) async {
        final archivos = <DriveEntry>[];
        for (final folderId in tree.paths.keys) {
          archivos.addAll(
            await _listChildren(token, folderId, soloCarpetas: false),
          );
        }
        return archivos;
      });

  /// Hijos directos de [parentId]: carpetas o archivos, nunca ambos.
  Future<List<DriveEntry>> _listChildren(
    String token,
    String parentId, {
    required bool soloCarpetas,
  }) async {
    final tipo = soloCarpetas
        ? "mimeType = '${DriveEntry.folderMimeType}'"
        : "mimeType != '${DriveEntry.folderMimeType}'";
    final query = "'$parentId' in parents and $tipo and trashed = false";

    final resultado = <DriveEntry>[];
    String? pageToken;

    do {
      final uri = Uri.parse(
        'https://www.googleapis.com/drive/v3/files'
        '?q=${Uri.encodeComponent(query)}'
        '&pageSize=200'
        '&fields=${Uri.encodeComponent('nextPageToken,files($_entryFields)')}'
        '${pageToken == null ? '' : '&pageToken=$pageToken'}',
      );

      final response =
          await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      _throwIfAuthProblem(response);
      if (response.statusCode != 200) {
        // Falla en vez de devolver lo que alcanzó a juntar. El listado
        // alimenta una reconciliación que borra lo que no aparece: media
        // respuesta se leería como "estos archivos ya no existen".
        throw Exception(
          'Drive respondió ${response.statusCode} al listar $parentId.',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      for (final raw in (data['files'] as List?) ?? const []) {
        if (raw is Map) {
          resultado.add(DriveEntry.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
      pageToken = data['nextPageToken']?.toString();
    } while (pageToken != null && pageToken.isNotEmpty);

    return resultado;
  }

  /// Último árbol conocido, para no recorrer Drive antes de cada borrado.
  BitacoraTree? _arbolCache;

  /// El árbol de Bitácora, recorriéndolo solo si no se conoce o si [refrescar].
  Future<BitacoraTree?> bitacoraTree(
      {bool refrescar = false, bool interactivo = true}) async {
    if (!refrescar && _arbolCache != null) return _arbolCache;
    _arbolCache = await loadBitacoraTree(interactivo: interactivo);
    return _arbolCache;
  }

  /// Si [fileId] está dentro de la carpeta Bitácora.
  ///
  /// Con `drive.file`, Google ya solo deja ver archivos que la app creó, así
  /// que esto es cinturón y tirantes, no la única barrera. Ante la duda —sin
  /// árbol, sin respuesta de Drive, error de red— devuelve false: no poder
  /// confirmar que algo es nuestro no autoriza a borrarlo.
  Future<bool> belongsToBitacora(String fileId) async {
    if (fileId.isEmpty || fileId.contains('/')) return false;

    try {
      return await _withToken((token) async {
        final response = await http.get(
          Uri.parse(
            'https://www.googleapis.com/drive/v3/files/$fileId?fields=id,parents',
          ),
          headers: {'Authorization': 'Bearer $token'},
        );
        _throwIfAuthProblem(response);
        if (response.statusCode != 200) return false;

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final parents = (data['parents'] as List?)
                ?.map((p) => p.toString())
                .toList(growable: false) ??
            const <String>[];
        if (parents.isEmpty) return false;

        var arbol = await bitacoraTree();
        if (arbol != null && parents.any(arbol.containsFolder)) return true;

        // Puede haber caído en una carpeta creada después del último recorrido.
        arbol = await bitacoraTree(refrescar: true);
        return arbol != null && parents.any(arbol.containsFolder);
      });
    } catch (e) {
      Logger.warning(
        'No se pudo confirmar si $fileId está en Bitácora: $e',
        tag: 'GoogleDriveService',
      );
      return false;
    }
  }

  /// Busca la carpeta "Bitácora" sin crearla, por nombre.
  ///
  /// Con `drive.file`, esta búsqueda solo encuentra la carpeta si la creó la
  /// propia app (en una sesión anterior, con éste u otro scope): es el único
  /// caso al que este permiso da acceso sin haber elegido nada en un
  /// selector.
  Future<String?> _findBitacoraFolder(String token) =>
      _searchBitacoraFolderByName(token);

  Future<String?> _searchBitacoraFolderByName(String token) async {
    final response = await http.get(
      Uri.parse(
        'https://www.googleapis.com/drive/v3/files'
        "?q=name%3D'Bit%C3%A1cora'+and+mimeType%3D'application%2Fvnd.google-apps.folder'+and+trashed%3Dfalse"
        '&fields=files(id%2Cname)',
      ),
      headers: {'Authorization': 'Bearer $token'},
    );
    _throwIfAuthProblem(response);
    if (response.statusCode != 200) return null;
    final files = (jsonDecode(response.body)['files'] as List?) ?? const [];
    return files.isEmpty ? null : files.first['id'] as String?;
  }

  /// Elimina el archivo del Drive del usuario.
  ///
  /// Solo dentro de la carpeta Bitácora: ver [belongsToBitacora]. Con permiso
  /// completo de Drive, un `fileId` equivocado acá borraría un archivo
  /// cualquiera de la persona.
  Future<bool> deleteFile(String fileId) async {
    if (!await belongsToBitacora(fileId)) {
      Logger.warning(
        'No se borra $fileId: está fuera de la carpeta Bitácora',
        tag: 'GoogleDriveService',
      );
      return false;
    }

    final token = await getOrRequestToken();
    if (token != null && token.isNotEmpty && !fileId.contains('/')) {
      try {
        final response = await http.delete(
          Uri.parse(
            'https://www.googleapis.com/drive/v3/files/$fileId',
          ),
          headers: {'Authorization': 'Bearer $token'},
        );
        return response.statusCode == 204 || response.statusCode == 200;
      } catch (e) {
        Logger.warning(
          'Error borrando archivo de Drive: $e',
          tag: 'GoogleDriveService',
        );
      }
    }
    return false;
  }

  /// Busca o crea la carpeta destino:
  /// `Bitácora/<carrera>/<asignatura>/[<subfolder>]`.
  ///
  /// El nivel de carrera se agregó para que el Drive del estudiante quede
  /// ordenado igual que su cabeza: primero la carrera, dentro las
  /// asignaturas, y dentro de cada una el material docente separado de los
  /// trabajos ([teachingMaterialFolderName]).
  ///
  /// Sin carrera se cae al esquema plano de antes (`Bitácora/<asignatura>`),
  /// que es donde viven los archivos subidos por versiones anteriores.
  ///
  /// Si algún nivel falla, devuelve el último que sí resolvió en vez de
  /// abortar: mejor que el archivo quede una carpeta más arriba a que la
  /// subida entera se pierda.
  Future<String?> _getOrCreateSubjectFolder(
    String token,
    String? subject, {
    String? career,
    String? subfolder,
  }) async {
    final rootFolderId = await _getOrCreateBitacoraFolder(token);
    if (rootFolderId == null) return null;

    var parentId = rootFolderId;
    if (career != null && career.trim().isNotEmpty) {
      parentId =
          await _getOrCreateChildFolder(token, career.trim(), parentId) ??
              parentId;
    }

    if (subject == null || subject.trim().isEmpty) return parentId;

    final subjectFolderId =
        await _getOrCreateChildFolder(token, subject.trim(), parentId) ??
            parentId;

    if (subfolder == null || subfolder.trim().isEmpty) return subjectFolderId;

    return await _getOrCreateChildFolder(token, subfolder.trim(), subjectFolderId) ??
        subjectFolderId;
  }

  /// Busca una carpeta [name] dentro de [parentId] y la crea si no existe.
  Future<String?> _getOrCreateChildFolder(
    String token,
    String name,
    String parentId,
  ) async {
    try {
      // Se listan las carpetas hijas y se comparan normalizadas, en vez de
      // preguntar por nombre exacto. Drive distingue tildes y mayúsculas: con
      // una búsqueda exacta, una carpeta "Teologia" creada a mano no calzaba
      // con la carrera "Teología" y la app creaba una segunda al lado.
      final query =
          "'$parentId' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false";

      final searchResp = await http.get(
        Uri.parse(
          'https://www.googleapis.com/drive/v3/files'
          '?q=${Uri.encodeComponent(query)}'
          '&fields=files(id%2Cname)',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (searchResp.statusCode == 401) throw _DriveAuthExpiredException();
      if (searchResp.statusCode == 200) {
        final files = (jsonDecode(searchResp.body)['files'] as List?) ?? [];
        final buscada = normalizeFolderName(name);
        for (final f in files) {
          if (f is Map &&
              f['name'] != null &&
              normalizeFolderName(f['name'].toString()) == buscada) {
            return f['id'] as String?;
          }
        }
      }

      final createResp = await http.post(
        Uri.parse('https://www.googleapis.com/drive/v3/files'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': name,
          'mimeType': 'application/vnd.google-apps.folder',
          'parents': [parentId],
        }),
      );

      if (createResp.statusCode == 401) throw _DriveAuthExpiredException();
      if (createResp.statusCode == 200 || createResp.statusCode == 201) {
        final id = (jsonDecode(createResp.body) as Map<String, dynamic>)['id'] as String?;
        Logger.info(
          'Carpeta "$name" creada en Google Drive. ID: $id',
          tag: 'GoogleDriveService',
        );
        return id;
      }
    } on _DriveAuthExpiredException {
      rethrow;
    } catch (e) {
      Logger.warning(
        'Error al buscar/crear carpeta "$name": $e',
        tag: 'GoogleDriveService',
      );
    }
    return null;
  }

  /// Busca o crea la carpeta "Bitácora" en "Mi unidad".
  Future<String?> _getOrCreateBitacoraFolder(String token) async {
    try {
      final searchResp = await http.get(
        Uri.parse(
          'https://www.googleapis.com/drive/v3/files'
          "?q=name%3D'Bit%C3%A1cora'+and+mimeType%3D'application%2Fvnd.google-apps.folder'+and+trashed%3Dfalse"
          '&fields=files(id%2Cname)',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (searchResp.statusCode == 401) throw _DriveAuthExpiredException();
      if (searchResp.statusCode == 200) {
        final files =
            (jsonDecode(searchResp.body)['files'] as List?) ?? [];
        if (files.isNotEmpty) return files.first['id'] as String?;
      }

      final createResp = await http.post(
        Uri.parse('https://www.googleapis.com/drive/v3/files'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': 'Bitácora',
          'mimeType': 'application/vnd.google-apps.folder',
        }),
      );

      if (createResp.statusCode == 401) throw _DriveAuthExpiredException();
      if (createResp.statusCode == 200 || createResp.statusCode == 201) {
        final id =
            (jsonDecode(createResp.body) as Map<String, dynamic>)['id']
                as String?;
        Logger.info(
          'Carpeta "Bitácora" creada en Google Drive. ID: $id',
          tag: 'GoogleDriveService',
        );
        return id;
      }
    } on _DriveAuthExpiredException {
      rethrow;
    } catch (e) {
      Logger.warning(
        'Error al buscar/crear carpeta Bitácora: $e',
        tag: 'GoogleDriveService',
      );
    }
    return null;
  }
}
