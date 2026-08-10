# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Bitácora is a Flutter app for academic task management with offline-first support and automatic Supabase sync & Google Drive file storage. Targets Android, iOS, Linux and Web. UI text and identifiers in this codebase are largely in Spanish.

## Commands

```bash
flutter pub get                  # install dependencies
flutter run                      # run the app
flutter analyze                  # static analysis (uses analysis_options.yaml / flutter_lints)
flutter test                     # run all unit tests (test/)
flutter test test/models_test.dart   # run a single test file
flutter test --plain-name "test name"  # run a single test by name
flutter test integration_test/   # run integration tests
flutter build apk / web / linux  # build for a platform
flutter build web --release --pwa-strategy=none   # web: ver nota abajo
firebase deploy --only hosting --project bitacora-2d643
```

### Despliegue web

Compilar **siempre** con `--pwa-strategy=none` y borrar `build/web/flutter_service_worker.js` antes de desplegar.

El service worker de Flutter cachea `main.dart.js` de forma agresiva y no lo suelta hasta dos recargas después del despliegue: cada cambio se veía "no aplicado" aunque estuviera en producción, y había que pedir Ctrl+Shift+R en cada iteración. Dejar el archivo fuera del despliegue hace que el navegador dé de baja el que ya tuviera registrado.

Bitácora se usa sobre todo en Android, así que el offline del navegador no compensa el costo de depurar contra una versión vieja.

## Architecture

### Directory structure (`lib/`)

- `lib/models/`: Data models (`task_model.dart`, `subject_model.dart`, `career_model.dart`, `meeting_model.dart`, `study_file_model.dart`).
- `lib/screens/`: All screen widgets (`*_screen.dart`).
- `lib/widgets/`: Reusable UI widgets (`task_card.dart`, `app_icon_widget.dart`).
- `lib/services/`: Services for Supabase, Google Drive, local cache, auth, meetings, study files, and sync.
- `lib/providers/`: State management providers (`app_state.dart`, `theme_provider.dart`).
- `lib/utils/`: Helper utilities and security validators.

### Data flow / offline-first

- `lib/providers/app_state.dart` (`AppState`, a `ChangeNotifier`) is the single source of truth for `Task` and `Subject` lists, consumed via `provider`.
- Loading pattern used throughout `AppState`: read from `LocalCacheService` (Hive) first and notify listeners immediately, then fetch from `SupabaseDbService` and update/notify again. Writes go to Supabase and are mirrored to the local cache.
- `SyncService` (singleton, `lib/services/sync_service.dart`) listens for connectivity changes via `connectivity_plus` and reconciles pending local changes with Supabase when connectivity returns.
- `GoogleDriveService` (`lib/services/google_drive_service.dart`) uploads study files into `Bitácora/<Carrera>/<Asignatura>/`, with `Material docente/` as a further subfolder for `category = 'guia'`.

### Google Drive: alcance y sincronización

La app pide el ámbito OAuth **`https://www.googleapis.com/auth/drive.file`** (acotado), en las tres puntas donde se pide (`auth_service.dart` al iniciar sesión, `drive_token_stub.dart` en móvil/desktop, `web/index.html` en web).

`drive.file` solo da acceso a los archivos y carpetas que la propia app creó: un archivo que alguien suba a Drive desde fuera de la app (la web de Drive, el explorador de archivos del teléfono) queda invisible para Bitácora, y sus borrados tampoco se detectan. Es una limitación conocida y aceptada a propósito — ver el porqué abajo — no un descuido.

Se probó el ámbito completo (`drive`) antes. Se volvió atrás: un ámbito restringido como ese le muestra a **cualquier** usuario la pantalla "Google no ha verificado esta aplicación" en el login, y limita el proyecto a 100 cuentas de prueba hasta pasar la verificación OAuth — que para `drive` completo exige además una auditoría CASA paga (cientos de USD anuales). `drive.file` no es un ámbito restringido, así que no arrastra ninguna de las dos cosas. El costo (no ver archivos agregados fuera de la app) se aceptó porque el flujo normal de la app es subir todo por su propio botón — para eso `drive.file` alcanza sin más.

Se evaluó primero un intermedio (`drive.file` + que el usuario eligiera su carpeta con el Google Picker, así el permiso cubriría también lo agregado a mano). Funcionaba — probado en vivo — pero se descartó: agrega un paso manual de configuración, y la app está pensada para gente que no sabe de informática. Mejor un único cartel de permiso, como el de cualquier app común, aunque cueste esa visibilidad.

`BitacoraTree` (en `google_drive_service.dart`) guarda los ids de la carpeta raíz y sus descendientes; `belongsToBitacora()` es la comprobación que corre antes de cada borrado o renombrado en Drive. Con `drive.file`, Google ya solo deja ver lo que la app creó, así que esto es cinturón y tirantes, no la única barrera — pero se conserva: ante la duda —sin árbol, sin respuesta, error de red— devuelve `false`, no poder confirmar que algo es nuestro no autoriza a tocarlo.

La detección de cambios usa la **Changes API** (`changes.list`): una sola consulta de diferencias que cubre agregados, borrados, renombrados y movimientos, acotada a lo que el ámbito deja ver (o sea, lo creado por la app). `StudyFileService.syncDriveChanges()` la aplica. El `pageToken` se guarda en la caja de Hive de archivos y **solo avanza si el ciclo entero terminó bien**, para que un fallo a mitad se reprocese en vez de perder cambios.

La ruta de la carpeta **es** la clasificación del archivo: `classifyDrivePath()` (`lib/utils/drive_path_classifier.dart`) deduce carrera, asignatura y categoría, y rechaza —sin inventar valores— lo que esté en carpetas que no lo permitan. La migración `supabase_hardening_16` exige que la asignatura pertenezca a la carrera, así que adivinar solo cambiaría un aviso claro por un INSERT rechazado.

**Migrar de `drive` a `drive.file` en un proyecto ya en uso** pide además sacar el ámbito `drive` completo de los scopes declarados en Google Cloud Console (OAuth consent screen) y, si Google lo pide para `drive.file`, pasar su verificación — más liviana que la de un ámbito restringido, sin auditoría CASA. Ese trámite es manual, en la consola de Google, no por código.

### Startup sequence (`lib/main.dart`)

Supabase init → Hive init → `LocalCacheService.initialize()` → `TaskProgressService.initialize()` → `CareerService.initialize()` → `ThemeProvider.initialize()` → `SyncService.initialize()` → (non-web) request notification/alarm permissions and init `NotificationService`. Startup errors are caught and routed to `StartupErrorScreen` rather than crashing.

### Logging

Use `Logger` (`lib/utils/logger.dart`) with a `tag` rather than `print`/`debugPrint`.

