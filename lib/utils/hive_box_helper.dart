import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import 'logger.dart';

const _openTimeout = Duration(seconds: 8);
const _deleteTimeout = Duration(seconds: 3);

/// Abre una caja Hive con recuperación si los datos locales están corruptos.
/// En web, `deleteBoxFromDisk` puede colgar; se aplica timeout para no bloquear el arranque.
Future<Box<T>> openHiveBoxSafely<T>(String name, {HiveCipher? cipher}) async {
  try {
    if (Hive.isBoxOpen(name)) {
      return Hive.box<T>(name);
    }
    return await Hive.openBox<T>(name, encryptionCipher: cipher).timeout(_openTimeout);
  } catch (e) {
    Logger.warning('Error abriendo caja Hive "$name": $e', tag: 'Hive');
    await _recoverHiveBox(name);
    return await Hive.openBox<T>(name, encryptionCipher: cipher).timeout(_openTimeout);
  }
}

Future<Box> openHiveBoxSafelyUntyped(String name, {HiveCipher? cipher}) async {
  try {
    if (Hive.isBoxOpen(name)) {
      return Hive.box(name);
    }
    return await Hive.openBox(name, encryptionCipher: cipher).timeout(_openTimeout);
  } catch (e) {
    Logger.warning('Error abriendo caja Hive "$name": $e', tag: 'Hive');
    await _recoverHiveBox(name);
    return await Hive.openBox(name, encryptionCipher: cipher).timeout(_openTimeout);
  }
}

Future<void> _recoverHiveBox(String name) async {
  try {
    if (Hive.isBoxOpen(name)) {
      await Hive.box(name).close();
    }
  } catch (e) {
    Logger.warning('No se pudo cerrar "$name": $e', tag: 'Hive');
  }

  try {
    await Hive.deleteBoxFromDisk(name).timeout(_deleteTimeout);
  } on TimeoutException {
    Logger.warning(
      'deleteBoxFromDisk("$name") excedió el tiempo — continuando',
      tag: 'Hive',
    );
    if (kIsWeb) {
      Logger.warning(
        'Si la app queda en blanco, borra IndexedDB del sitio en DevTools',
        tag: 'Hive',
      );
    }
  } catch (e) {
    Logger.warning('deleteBoxFromDisk("$name") falló: $e', tag: 'Hive');
  }
}
