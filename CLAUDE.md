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

La app pide el ámbito OAuth **`https://www.googleapis.com/auth/drive`** (completo), no `drive.file`.

`drive.file` solo da acceso a los archivos que la propia app creó: un archivo que el usuario sube a Drive desde el computador era invisible para Bitácora, y los borrados hechos fuera de la app no se podían detectar. Google **no ofrece** un ámbito acotado a una carpeta (existía en la API v2, no en la v3), así que es todo el Drive o nada.

**La restricción a la carpeta Bitácora la impone el código, no Google.** `BitacoraTree` (en `google_drive_service.dart`) guarda los ids de la carpeta raíz y sus descendientes; `belongsToBitacora()` es la comprobación que corre antes de cada borrado o renombrado en Drive. Ante la duda —sin árbol, sin respuesta, error de red— devuelve `false`: no poder confirmar que algo es nuestro no autoriza a tocarlo.

La detección de cambios usa la **Changes API** (`changes.list`): una sola consulta de diferencias que cubre agregados, borrados, renombrados y movimientos. `StudyFileService.syncDriveChanges()` la aplica. El `pageToken` se guarda en la caja de Hive de archivos y **solo avanza si el ciclo entero terminó bien**, para que un fallo a mitad se reprocese en vez de perder cambios.

La ruta de la carpeta **es** la clasificación del archivo: `classifyDrivePath()` (`lib/utils/drive_path_classifier.dart`) deduce carrera, asignatura y categoría, y rechaza —sin inventar valores— lo que esté en carpetas que no lo permitan. La migración `supabase_hardening_16` exige que la asignatura pertenezca a la carrera, así que adivinar solo cambiaría un aviso claro por un INSERT rechazado.

**Consecuencia operativa:** al ser un ámbito restringido, Google muestra la pantalla "esta app no está verificada" una vez por usuario, y el proyecto queda limitado a 100 usuarios de prueba mientras no pase la verificación OAuth (que para Drive incluye auditoría CASA). Publicar en Google Play no la quita: son trámites distintos.

### Startup sequence (`lib/main.dart`)

Supabase init → Hive init → `LocalCacheService.initialize()` → `TaskProgressService.initialize()` → `CareerService.initialize()` → `ThemeProvider.initialize()` → `SyncService.initialize()` → (non-web) request notification/alarm permissions and init `NotificationService`. Startup errors are caught and routed to `StartupErrorScreen` rather than crashing.

### Logging

Use `Logger` (`lib/utils/logger.dart`) with a `tag` rather than `print`/`debugPrint`.

