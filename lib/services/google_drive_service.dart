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

class GoogleDriveService {
  static final GoogleDriveService _instance = GoogleDriveService._internal();
  factory GoogleDriveService() => _instance;
  GoogleDriveService._internal();

  static const _tokenKey = 'google_drive_access_token';

  /// Subcarpeta donde va el material docente, dentro de la carpeta de cada
  /// asignatura. Separarlo de los trabajos no es solo orden: como
  /// [scanBitacoraFolderFiles] registra automáticamente lo que encuentra,
  /// tener las guías en la misma carpeta las duplicaba en "Mis tareas".
  static const String teachingMaterialFolderName = 'Material docente';

  // El token de acceso a Drive se guarda cifrado (Keystore/Keychain vía
  // flutter_secure_storage), igual que la clave de cifrado de Hive — antes
  // se guardaba en texto plano con SharedPreferences.
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Persiste el token de Drive de forma segura.
  static Future<void> persistToken(String token) async {
    if (token.isEmpty) return;
    await _secureStorage.write(key: _tokenKey, value: token);
    Logger.info('Token de Drive guardado de forma segura.', tag: 'GoogleDriveService');
  }

  /// Limpia el token al cerrar sesión.
  static Future<void> clearToken() async {
    await _secureStorage.delete(key: _tokenKey);
  }

  /// Obtiene el token disponible. Orden de prioridad:
  /// 1. Sesión activa de Supabase (providerToken)
  /// 2. Token guardado en almacenamiento seguro
  Future<String?> get _storedToken async {
    final sessionToken =
        Supabase.instance.client.auth.currentSession?.providerToken;
    if (sessionToken != null && sessionToken.isNotEmpty) {
      await persistToken(sessionToken);
      return sessionToken;
    }
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

  /// Pide un token nuevo saltándose el cache (Supabase providerToken /
  /// storage), a diferencia de [getOrRequestToken]. Se usa al reintentar
  /// tras un 401: en Web, el providerToken de Supabase no se refresca solo,
  /// así que reusar [getOrRequestToken] devolvería el mismo token vencido.
  Future<String?> _requestFreshToken() async {
    final token = await requestDriveTokenPlatform(_googleClientId);
    if (token != null && token.isNotEmpty) {
      await persistToken(token);
      return token;
    }
    return null;
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
    String? subject,
    String? subfolder,
  }) async {
    final folderId = await _getOrCreateSubjectFolder(token, subject, subfolder: subfolder);
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

  /// Hace público el archivo en Drive.
  Future<String> makeFilePubliclySharable(String fileId) async {
    final token = await getOrRequestToken();
    if (token != null && token.isNotEmpty && !fileId.contains('/')) {
      try {
        await http.post(
          Uri.parse(
            'https://www.googleapis.com/drive/v3/files/$fileId/permissions',
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'role': 'reader', 'type': 'anyone'}),
        );
      } catch (e) {
        Logger.warning(
          'No se pudo hacer público el archivo: $e',
          tag: 'GoogleDriveService',
        );
      }
    }
    return 'https://drive.google.com/file/d/$fileId/view?usp=sharing';
  }

  /// Verifica si un archivo existe y no está en la papelera en Google Drive.
  Future<bool> checkFileExists(String fileId) async {
    if (fileId.isEmpty || fileId.contains('/')) return false;
    final token = await getOrRequestToken();
    if (token == null || token.isEmpty) return true; // Si no hay token, no asumimos borrado

    try {
      final response = await http.get(
        Uri.parse(
          'https://www.googleapis.com/drive/v3/files/$fileId?fields=id,trashed',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final isTrashed = data['trashed'] == true;
        return !isTrashed;
      } else if (response.statusCode == 404) {
        return false;
      }
    } catch (e) {
      Logger.warning('Error verificando existencia de archivo $fileId en Drive: $e', tag: 'GoogleDriveService');
    }
    return true;
  }

  /// Escanea la carpeta "Bitácora" y sus subcarpetas en Google Drive.
  /// Devuelve los archivos encontrados con su metadato y asignatura asignada por carpeta.
  Future<List<Map<String, dynamic>>> scanBitacoraFolderFiles() async {
    final token = await getOrRequestToken();
    if (token == null || token.isEmpty) return [];

    try {
      final rootFolderId = await _getOrCreateBitacoraFolder(token);
      if (rootFolderId == null) return [];

      // 1. Obtener todas las subcarpetas dentro de "Bitácora" (Mapeo: folderId -> subjectName)
      //
      // Solo se baja un nivel, y de eso depende que el material docente no se
      // registre como trabajo: vive en `<asignatura>/Material docente/`, un
      // nivel más abajo, así que su carpeta nunca entra en folderMap y sus
      // archivos quedan fuera de la consulta del paso 2.
      final folderMap = <String, String>{rootFolderId: 'General'};

      final subfoldersResp = await http.get(
        Uri.parse(
          'https://www.googleapis.com/drive/v3/files'
          '?q=${Uri.encodeComponent("'$rootFolderId' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false")}'
          '&fields=files(id%2Cname)',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (subfoldersResp.statusCode == 200) {
        final subfolders = (jsonDecode(subfoldersResp.body)['files'] as List?) ?? [];
        for (final sf in subfolders) {
          if (sf is Map && sf['id'] != null && sf['name'] != null) {
            folderMap[sf['id'].toString()] = sf['name'].toString();
          }
        }
      }

      // 2. Obtener todos los archivos en cualquiera de estas carpetas
      final parentQueries = folderMap.keys.map((id) => "'$id' in parents").join(' or ');
      final filesQuery = "($parentQueries) and mimeType != 'application/vnd.google-apps.folder' and trashed = false";

      final filesResp = await http.get(
        Uri.parse(
          'https://www.googleapis.com/drive/v3/files'
          '?q=${Uri.encodeComponent(filesQuery)}'
          '&fields=files(id%2Cname%2CmimeType%2Csize%2Cparents)',
        ),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (filesResp.statusCode == 200) {
        final rawFiles = (jsonDecode(filesResp.body)['files'] as List?) ?? [];
        final result = <Map<String, dynamic>>[];

        for (final f in rawFiles) {
          if (f is Map && f['id'] != null) {
            final fileId = f['id'].toString();
            final parents = (f['parents'] as List?) ?? [];
            String subject = 'General';

            for (final p in parents) {
              if (folderMap.containsKey(p.toString())) {
                subject = folderMap[p.toString()]!;
                break;
              }
            }

            result.add({
              'drive_file_id': fileId,
              'name': f['name']?.toString() ?? 'Sin nombre',
              'mime_type': f['mimeType']?.toString() ?? 'application/octet-stream',
              'size_bytes': int.tryParse(f['size']?.toString() ?? '0') ?? 0,
              'drive_link': 'https://drive.google.com/file/d/$fileId/view?usp=sharing',
              'subject': subject,
            });
          }
        }
        return result;
      }
    } catch (e) {
      Logger.error('Error escaneando carpetas de Drive: $e', tag: 'GoogleDriveService');
    }
    return [];
  }

  /// Elimina el archivo del Drive del usuario.
  Future<bool> deleteFile(String fileId) async {
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

  /// Busca o crea la carpeta destino: `Bitácora/<asignatura>`, y dentro de
  /// ella `<subfolder>` si se pide (el material docente va a
  /// [teachingMaterialFolderName] para no mezclarse con los trabajos).
  ///
  /// Si algún nivel falla, devuelve el último que sí resolvió en vez de
  /// abortar: mejor que el archivo quede una carpeta más arriba a que la
  /// subida entera se pierda.
  Future<String?> _getOrCreateSubjectFolder(
    String token,
    String? subject, {
    String? subfolder,
  }) async {
    final rootFolderId = await _getOrCreateBitacoraFolder(token);
    if (rootFolderId == null) return null;
    if (subject == null || subject.trim().isEmpty) return rootFolderId;

    final subjectFolderId =
        await _getOrCreateChildFolder(token, subject.trim(), rootFolderId) ??
            rootFolderId;

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
      // Escapar comillas simples para la query de Drive API
      final escapedName = name.replaceAll("'", "\\'");
      final query = "name = '$escapedName' and '$parentId' in parents and mimeType = 'application/vnd.google-apps.folder' and trashed = false";

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
        if (files.isNotEmpty) {
          return files.first['id'] as String?;
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
