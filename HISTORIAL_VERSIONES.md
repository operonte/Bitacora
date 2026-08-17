# Historial de versiones — Bitácora

Archivo de control para poder **volver atrás** si una versión sale mal. Cada
entrada anota el commit exacto que se compiló y publicó, qué cambió y qué se
probó de verdad (no lo que se supone que anda).

Se actualiza a mano en cada versión que se publica, después de commitear.

## Cómo restablecer una versión anterior

Mirar la tabla, sacar el hash y elegir según el caso:

```bash
# 1. Ver cómo estaba el código en esa versión, sin tocar nada
git checkout <hash>

# 2. Volver a master dejando las cosas como estaban
git checkout master

# 3. Deshacer los cambios de una versión, conservando el historial
#    (crea un commit nuevo que revierte; es lo más seguro)
git revert <hash>

# 4. Reconstruir y volver a publicar desde esa versión
git checkout <hash>
flutter build apk --release
flutter build web --release --pwa-strategy=none
rm -f build/web/flutter_service_worker.js
firebase deploy --only hosting --project bitacora-2d643
```

**No usar `git reset --hard` sobre master si ya se hizo push**: reescribe
historial que ya está publicado en GitHub. Para eso está `git revert`.

El APK de cada versión queda además en GitHub Releases
(https://github.com/operonte/Bitacora/releases), así que para volver atrás
**solo en el teléfono** alcanza con descargar el APK viejo e instalarlo — no
hace falta compilar nada.

---

## Versiones

| Versión | Commit | Fecha | Qué cambió |
|---|---|---|---|
| **2.11.0** | `f3e6374` | 2026-08-17 | Archivos grandes sin cerrar la app, límite 250 MB, progreso de subida |
| 2.10.1 | `fc58188` | 2026-08-10 | Corrige hora de reuniones (huso horario) |
| 2.10.0 | `7011a55` | 2026-08-10 | Materias por semestre, filtros y carga de mallas curriculares |
| 2.9.0 | `d562dc7` | 2026-08-10 | Carreras desactivables, Drive sin aviso de app no segura, auditoría de seguridad |
| 2.8.2 | `24eb066` | 2026-08-08 | Sincronización real con Google Drive vía Changes API |
| 2.8.1 | `b0b1e71` | 2026-08-08 | Carrera y asignatura obligatorias, fuera el escaneo de Drive |
| 2.8.0 | `35d16a6` | 2026-08-08 | Notificaciones de nuevo, archivos en su lugar, panel sin contraseña compartida |
| 2.7.1 | `e0b7490` | 2026-08-08 | Arranque que no muere, cierre de sesión que limpia, carrera en los archivos |
| 2.7.0 | `3b14627` | 2026-08-05 | Reuniones compartidas por carrera y notificaciones que sí llegan |
| 2.6.1 | `608ac0c` | 2026-08-05 | Arregla crash de Material docente por locale sin inicializar |
| 2.6.0 | `9ed083f` | 2026-08-03 | Unifica material docente con los archivos, filtra reuniones por carrera |
| 2.5.1 | `ba5d120` | 2026-08-03 | Arregla la autoría de tareas compartidas al editarlas |
| 2.5.0 | `99ed248` | 2026-08-03 | Cierra RLS y agrega autoría en tareas compartidas |
| 2.4.4 | `7b79905` | 2026-08-03 | Reuniones recurrentes y recordatorios más confiables |
| 2.4.3 | `d321972` | 2026-08-03 | Arregla subida de archivos a Google Drive |
| 2.4.2 | `7599737` | 2026-08-02 | Arregla notificaciones que nunca llegaban |

---

## 2.11.0 — `f3e6374` — 2026-08-17

**Publicado en**: APK release `2.11.0+46` (GitHub Releases) y web
(`bitacora-2d643.web.app`).

### Qué se arregló

Subir un video de ~111 MB **cerraba la app en Android** en cuanto se elegía el
archivo, antes de que la subida empezara. El selector pedía el archivo entero
como arreglo de bytes (`withData: true`): eso supera el techo de memoria que
Android le da a cada app y lanza `OutOfMemoryError`, que es un `Error` y no una
`Exception`, así que el plugin no lo atrapaba y el proceso moría sin mensaje.

### Qué cambió

- `lib/utils/picker_stub.dart`: `withData: false`; devuelve la ruta en disco y
  solo los primeros 4 KB (`CustomFilePicker.headBytes`), que es todo lo que
  mira la validación de magic bytes.
- `lib/services/drive_upload_stub.dart` (nuevo): manda el cuerpo por streaming
  en un **único PUT**, no por trozos. `IOClient` hace `stream.pipe`, que respeta
  contrapresión: la memoria se queda en el búfer de red sin importar cuánto pese
  el archivo. Medido: 250 MB suben creciendo 11,6 MB de RSS.
- `lib/services/drive_upload_web.dart` (nuevo): en web no cambia el camino — el
  navegador ya tiene el archivo en memoria y no hay techo por pestaña.
- `lib/utils/file_security_validator.dart`: límite de 50 MB a **250 MB**
  (`maxFileSizeMb`).
- `lib/screens/area_personal_screen.dart`: porcentaje de subida en el botón y el
  FAB, refrescado cada 1% para no disparar miles de `setState`; y se limpian las
  copias temporales que el selector deja en la caché de la app.

### Qué se probó

- `flutter analyze` limpio; 118 tests pasan (5 nuevos en
  `test/drive_upload_stub_test.dart`).
- En un **moto g86 power 5G (Android 16)**, con el video que fallaba:
  - build **debug**: subió en 30 s, sin `OutOfMemoryError` ni kill del sistema
    en `adb logcat -b all`; id de Drive `1Ad0xr9CL0UdfWS_obE7a86dEVKEX99IT`.
  - **APK release `2.11.0+46`**: subió por las **dos rutas** (archivos propios y
    material docente), con el porcentaje andando, y Google procesó el video
    después. Verificado mirando la app, no por log: un build release no escribe
    logs porque `Logger._enabled = kDebugMode`.

### Riesgo conocido

El techo de 250 MB no se probó contra un archivo de ese tamaño en un teléfono
con poca RAM libre. Si aparecen cierres con archivos mucho más grandes que 111
MB, el sospechoso es la copia que Android hace del archivo a la caché de la app
al elegirlo (previa a nuestro código), no la subida.

### Cómo diagnosticar si vuelve a pasar

```bash
adb devices -l                      # teléfono en modo depuración por USB
adb logcat -c -b all                # limpiar antes de reproducir
adb logcat -b all -v threadtime > /tmp/logcat.txt &
flutter run -d <id> --debug         # además da los logs Dart en vivo
```

Reproducir el cierre y buscar en el log `FATAL EXCEPTION`, `OutOfMemoryError`,
`Fatal signal`, `lmk_kill`. **No inferir la causa sin el log**: ya pasó una vez
que se dedujo mal y el arreglo no sirvió.
