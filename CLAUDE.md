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
```

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
- `GoogleDriveService` (`lib/services/google_drive_service.dart`) uploads study files into subject-specific subfolders (`Bitácora/<Asignatura>/`) on Google Drive.

### Startup sequence (`lib/main.dart`)

Supabase init → Hive init → `LocalCacheService.initialize()` → `TaskProgressService.initialize()` → `CareerService.initialize()` → `ThemeProvider.initialize()` → `SyncService.initialize()` → (non-web) request notification/alarm permissions and init `NotificationService`. Startup errors are caught and routed to `StartupErrorScreen` rather than crashing.

### Logging

Use `Logger` (`lib/utils/logger.dart`) with a `tag` rather than `print`/`debugPrint`.

