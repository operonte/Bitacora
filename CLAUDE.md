# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Bitácora is a Flutter app for academic task management with offline-first support and automatic Firebase sync. Targets Android, iOS, Linux and Web. UI text and identifiers in this codebase are largely in Spanish.

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

### Data flow / offline-first

- `lib/providers/app_state.dart` (`AppState`, a `ChangeNotifier`) is the single source of truth for `Task` and `Subject` lists, consumed via `provider`. Screens read from `AppState`, not directly from Firebase.
- Loading pattern used throughout `AppState`: read from `LocalCacheService` (Hive) first and notify listeners immediately, then fetch from `FirebaseService` (Firestore) and update/notify again. Writes go to Firebase and are mirrored to the local cache.
- `SyncService` (singleton, `lib/services/sync_service.dart`) listens for connectivity changes via `connectivity_plus` and reconciles pending local changes with Firestore when connectivity returns. It exposes `statusStream` (`SyncStatus`: idle/syncing/completed/partialError/error) for UI sync indicators.
- `TaskProgressService` tracks per-user completion/submission progress for *shared* tasks (tasks with `collaborators`), since a shared task's `isCompleted`/`isSubmitted` state can differ per user. `AppState.loadTasks()` overlays this per-user progress onto the shared task data after fetching.
- `FirebaseService` (`lib/firebase_service.dart`) wraps all Firestore/Auth reads and writes.

### Models

- `Task` (`lib/task_model.dart`) and `Subject` (`lib/subject_model.dart`) self-validate in their constructors (throw `ArgumentError` on invalid data, e.g. empty title, length limits).
- `CareerModel` (`lib/models/career_model.dart`) represents predefined "carreras" (academic programs), each with an access key and a set of subjects, managed via `CareerService` / `CareerFirestoreService`.

### Screens vs. providers/services

- Top-level screens (`*_screen.dart` in `lib/`) are split by task status: `pending_tasks_screen.dart`, `overdue_tasks_screen.dart`, `delivered_tasks_screen.dart`, corresponding to `AppState.pendingTasks` / `overdueTasks` / `deliveredTasks` getters (computed from `dueDate` and `isCompleted`/`isSubmitted`).
- `ThemeProvider` (`lib/providers/theme_provider.dart`) and `CareerService` are also registered as top-level `ChangeNotifierProvider`s in `main.dart`.
- Auth flow: `AuthService` + `AuthScreen`, with `AdminAuthService` for admin-only screens (`administration_screen.dart`).

### Startup sequence (`lib/main.dart`)

Firebase init → Hive init → `LocalCacheService.initialize()` → `TaskProgressService.initialize()` → `CareerService.initialize()` → `ThemeProvider.initialize()` → `SyncService.initialize()` → (non-web) request notification/alarm permissions and init `NotificationService`. Startup errors are caught and routed to `StartupErrorScreen` rather than crashing.

### Logging

Use `Logger` (`lib/utils/logger.dart`) with a `tag` rather than `print`/`debugPrint`.

## Testing notes

- `fake_cloud_firestore`, `firebase_auth_mocks`, `hive_test`, and `mockito` are used to mock Firebase/Hive in tests. `SyncService.test(...)` and similar `.test()` constructors exist on services for dependency injection of mocks.
