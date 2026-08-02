# Bitácora

Aplicación Flutter de gestión de tareas académicas con soporte offline-first y sincronización automática con Firebase.

## Características

- **Gestión de tareas**: Crear, editar, eliminar y organizar tareas académicas
- **Clasificación por estado**: Tareas pendientes, vencidas y entregadas
- **Sistema de urgencia**: Indicadores visuales (urgente, alta, media, baja, vencida)
- **Gestión de materias**: Crear materias con diferentes niveles de visibilidad
- **Sistema de carreras**: Carreras predefinidas con materias incluidas
- **Autenticación**: Google Sign-In con Firebase Auth
- **Soporte offline**: Caché local con Hive, funciona sin internet
- **Sincronización automática**: Sincronización con Firebase al recuperar conexión
- **Notificaciones**: Recordatorios diarios y notificaciones por tarea
- **Multiplataforma**: Android, iOS, Linux y Web

## Arquitectura

- **State Management**: Provider
- **Base de datos**: Firebase Firestore
- **Caché local**: Hive
- **Validación de formularios**: Validadores personalizados
- **Arquitectura de servicios**: Separación de responsabilidades (FirebaseService, SyncService, LocalCacheService, etc.)

## Instalación

### Prerrequisitos

- Flutter SDK (>= 3.11.4)
- Dart SDK (>= 3.11.4)
- Firebase project configurado
- Android Studio / VS Code

### Pasos

1. Clonar el repositorio:
```bash
git clone <repository-url>
cd Bitacora
```

2. Instalar dependencias:
```bash
flutter pub get
```

3. Configurar Firebase:
   - Crear proyecto en [Firebase Console](https://console.firebase.google.com/)
   - Agregar apps Android/iOS/Web
   - Descargar `google-services.json` (Android) y/o `GoogleService-Info.plist` (iOS)
   - Colocar los archivos en las ubicaciones correspondientes
   - Configurar Firestore y Authentication en Firebase Console

4. Ejecutar la app:
```bash
flutter run
```

## Uso

### Primeros pasos

1. Inicia sesión con Google
2. Selecciona o crea una carrera (usa la clave de acceso correspondiente)
3. Agrega tus materias
4. Crea tus tareas con fechas de entrega
5. La app te notificará sobre tareas próximas a vencer

### Claves de acceso para carreras

- **Teología**: `teologia2026`
- **Primero Medio A**: `primero_medio_a`
- **Octavo A**: `octavo_a`

## Tests

Ejecutar tests unitarios:
```bash
flutter test
```

Ejecutar tests de integración:
```bash
flutter test integration_test/
```

## Estructura del proyecto

```
lib/
├── main.dart                 # Punto de entrada
├── models/                   # Modelos de datos
│   ├── career_model.dart
│   ├── subject_model.dart
│   └── task_model.dart
├── providers/                # State management
│   └── app_state.dart
├── services/                 # Lógica de negocio
│   ├── career_service.dart
│   ├── local_cache_service.dart
│   └── sync_service.dart
├── screens/                  # Pantallas principales
├── utils/                    # Utilidades
│   ├── validators.dart
│   └── error_handler.dart
├── firebase_service.dart     # Servicio Firebase
├── notification_service.dart # Servicio de notificaciones
└── auth_service.dart         # Servicio de autenticación
```

## Tecnologías

- **Flutter**: UI framework
- **Firebase**: Backend (Auth, Firestore)
- **Hive**: Caché local
- **Provider**: State management
- **connectivity_plus**: Detección de conectividad
- **flutter_local_notifications**: Notificaciones locales

## Contribución

Las contribuciones son bienvenidas. Por favor:
1. Fork el proyecto
2. Crea una rama para tu feature
3. Commit tus cambios
4. Push a la rama
5. Abre un Pull Request

## Licencia

Este proyecto es privado y propiedad del desarrollador.

## Soporte

Para reportar bugs o solicitar features, abre un issue en el repositorio.
