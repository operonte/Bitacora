import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive/hive.dart';

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

    String? keyBase64 = await storage.read(key: _keyName);
    if (keyBase64 == null) {
      final key = Hive.generateSecureKey();
      keyBase64 = base64UrlEncode(key);
      await storage.write(key: _keyName, value: keyBase64);
    }

    _cipher = HiveAesCipher(base64Url.decode(keyBase64));
  }
}
