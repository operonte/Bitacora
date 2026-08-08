import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

import '../utils/logger.dart';

/// Gestiona la clave AES-256 usada para cifrar las cajas Hive locales.
///
/// La clave se genera aleatoriamente en el primer arranque y se persiste en el
/// almacenamiento seguro del sistema operativo (Android Keystore en Android,
/// Keychain en iOS, Secret Service en Linux). En web no se aplica cifrado
/// porque Hive web (IndexedDB) no admite HiveCipher.
class EncryptionService {
  static const _keyName = 'hive_encryption_key';
  static HiveCipher? _cipher;

  static HiveCipher? get cipher => _cipher;

  static Future<void> initialize() async {
    if (kIsWeb) return;

    const storage = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );

    String? keyBase64;
    try {
      keyBase64 = await storage.read(key: _keyName);
    } catch (e) {
      // BadPaddingException / BAD_DECRYPT: el almacenamiento seguro quedó
      // ilegible. Pasa sobre todo si Android restauró una copia de seguridad
      // de los datos de la app pero no la clave del Keystore, que nunca se
      // respalda. Antes esto dejaba la app muerta en el arranque para
      // siempre, sin más salida que borrar los datos a mano.
      Logger.error(
        'Almacenamiento seguro ilegible, se regenera la clave de cifrado',
        error: e,
        tag: 'Encryption',
      );
      keyBase64 = null;
      await _recoverFromUnreadableStorage(storage);
    }

    if (keyBase64 == null) {
      final key = Hive.generateSecureKey();
      keyBase64 = base64UrlEncode(key);
      try {
        await storage.write(key: _keyName, value: keyBase64);
      } catch (e) {
        // Sin persistir la clave el cifrado no sobrevive al próximo arranque,
        // pero es preferible a no abrir la app: la caché local se regenera
        // desde Supabase.
        Logger.error('No se pudo guardar la clave de cifrado',
            error: e, tag: 'Encryption');
      }
    }

    _cipher = HiveAesCipher(base64Url.decode(keyBase64));
  }

  /// Cajas que hay que borrar si se pierde la clave. Se listan por nombre a
  /// propósito: Hive.deleteFromDisk() solo alcanza las cajas ya abiertas, y
  /// acá todavía no se abrió ninguna, así que no serviría de nada.
  static const _boxNames = <String>[
    'tasks_cache',
    'subjects_cache',
    'metadata_cache',
    'meetings_box',
    'study_files_box',
    'teaching_materials_box',
    'task_progress',
  ];

  /// Deja el dispositivo en estado de primer arranque: sin clave vieja y sin
  /// cajas locales, porque con la clave perdida ya no hay forma de
  /// descifrarlas. Solo se pierde la caché — tareas, materias y reuniones
  /// vuelven a bajarse de Supabase al iniciar sesión.
  static Future<void> _recoverFromUnreadableStorage(
    FlutterSecureStorage storage,
  ) async {
    try {
      await storage.deleteAll();
    } catch (e) {
      Logger.warning('No se pudo limpiar el almacenamiento seguro: $e',
          tag: 'Encryption');
    }
    for (final name in _boxNames) {
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (e) {
        Logger.warning('No se pudo borrar la caja $name: $e',
            tag: 'Encryption');
      }
    }
  }
}
