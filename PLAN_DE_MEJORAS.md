# Bitácora — Plan de mejoras

Basado en la lectura completa del código a **v2.7.1** (`e0b7490`). Compañero de [FUNCIONALIDADES.md](FUNCIONALIDADES.md).

> **Estado de la ejecución.** Los puntos marcados **HECHO** están aplicados en el árbol de trabajo, sin commitear todavía. Verificado: `flutter analyze` limpio y `flutter test` con 83 pruebas en verde. **Falta probar en un teléfono** — nada de esto se ha instalado como APK.
>
> Hechos: 1.1–1.8, 2.1, 2.2, 2.3, 2.4, 3.2, 3.6, 4.1–4.7, 5.1.
> A medias: 3.1 (duplicación fuera, faltan las pestañas), 3.3 (pruebas nuevas, faltan servicios), 3.4 (lectura unificada, falta la escritura).
> Pendientes: 3.5, 3.7, 5.2.

Cada punto trae: qué pasa, dónde, por qué importa y qué haría. El esfuerzo es una estimación gruesa: **S** = una tarde, **M** = un par de días, **L** = más que eso.

Orden dentro de cada bloque: lo que más duele primero.

---

## Prioridad 1 — Corrección de datos

Cosas que pueden hacer que un estudiante vea información falsa o pierda algo. Nada de esto es teórico: el punto 1.1 ya te pasó ayer.

### 1.1 — Las carreras locales y las del servidor son dos verdades independientes  ·  **HECHO (opción A)**

**Dónde**: [career_service.dart:39](lib/services/career_service.dart#L39) (`getCareers` lee de Hive), [supabase_db_service.dart:155](lib/services/supabase_db_service.dart#L155) (`registerCareerMemberships` solo comprueba).

La lista de carreras vive en Hive y se mantiene sola. Las membresías viven en `user_careers` y son lo único que las políticas RLS miran. Nada las reconcilia. `registerCareerMemberships()` detecta exactamente la desincronización y escribe un `Logger.warning` que nadie ve.

El resultado es el peor tipo de fallo: la app se ve perfectamente bien. La carrera aparece en la lista, el título de la pantalla la muestra, se pueden crear tareas con ella. Simplemente no llega nada de lo que otros comparten, y no hay ninguna pista de por qué.

**Qué haría**: invertir la dirección. Que `user_careers` sea la fuente de verdad y la lista local pase a ser su caché.

1. Al iniciar sesión y en cada `forceSync`, traer `user_careers` del servidor.
2. Reconciliar: las carreras que el servidor confirma se guardan en Hive con su nombre resuelto; las que están en Hive pero no en el servidor **no se pueden auto-reparar** — entrar exige la clave de acceso, y ese es justamente el control que protege la carrera.
**Implementado (opción A)**: `CareerService.syncMembershipsFromServer()` reconcilia en las dos direcciones — quita del teléfono lo que el servidor no reconoce y agrega lo que sí (haber entrado desde otro dispositivo). Corre al arrancar y en cada `onAuthStateChange` con sesión. Sin conexión no toca nada: no se puede distinguir "no eres miembro" de "no pude preguntar", y ante la duda no se le quita nada al usuario.

Para que sacar una carrera no sea otro fallo mudo, la pantalla de clave explica una sola vez qué carrera se quitó y por qué.

De paso desapareció `SupabaseDbService.registerCareerMemberships()`: solo escribía un warning y costaba una consulta de red en cada carga de tareas, cada creación de tarea y cada guardado de reunión. Ahora la reconciliación ocurre una vez, al iniciar sesión.

**Queda disponible la opción B** — un RPC `admin_add_member(career_id, email)` protegido por `is_admin()`, para inscribir gente sin repartir claves. No es urgente ahora que la contradicción no se puede producir, pero sigue siendo la forma cómoda de resolver "a mi compañero no le llegan las reuniones".

⚠️ **Efecto al actualizar**: quien tenga una carrera en el teléfono sin membresía en el servidor la perderá al abrir la app y tendrá que reingresar la clave. Es exactamente el caso que estaba roto en silencio, pero hay que decirlo en las notas de la versión.

---

### 1.2 — Una edición que el servidor rechaza se ve como guardada  ·  **HECHO**

**Dónde**: [supabase_db_service.dart:281-288](lib/services/supabase_db_service.dart#L281-L288).

```dart
await _client.from(primaryTable).update(row).eq('id', task.id!);
```

PostgREST **no lanza** cuando un `update` no toca ninguna fila: si RLS filtra la fila, la respuesta es un 200 con cero filas afectadas. El `catch` de abajo nunca se dispara, se ejecuta `_cache.cacheTask(task)` y la interfaz muestra "✓ Tarea actualizada".

El usuario ve su cambio en pantalla. En el servidor no pasó nada. En la siguiente sincronización el cambio desaparece sin explicación.

**Qué haría**: `.update(row).eq('id', id).select()` y verificar que vuelva al menos una fila; si vuelve vacío, lanzar. De paso desaparece el `try/catch` que reintenta en la *otra* tabla (`tasks` ↔ `shared_tasks`), que hoy enmascara el error real y puede escribir en la tabla equivocada.

**Esfuerzo**: S.

---

### 1.3 — Un fallo parcial de red borra tareas de la caché  ·  **HECHO**

**Dónde**: [supabase_db_service.dart:383-412](lib/services/supabase_db_service.dart#L383-L412) y [:449](lib/services/supabase_db_service.dart#L449).

`getTasks()` consulta las tareas compartidas **carrera por carrera** dentro de un bucle, y cada iteración tiene su propio `try/catch` que solo registra un warning. Al terminar llama `_cache.replaceCachedTasks(tasks)`, que **vacía la caja** y la vuelve a llenar.

Si una de esas consultas falla por un corte de red de dos segundos, sus tareas no están en `tasks`, la caché se reemplaza sin ellas, y el usuario se queda sin las tareas de esa carrera hasta la próxima sincronización exitosa. Estando offline, sin ninguna.

**Qué haría**: llevar una bandera de "alguna consulta falló" y, si está encendida, hacer `cacheTasks` (fusiona) en vez de `replaceCachedTasks` (reemplaza). El reemplazo total solo cuando la lectura fue completa.

**Esfuerzo**: S.

---

### 1.4 — Una consulta por carrera, más una de rescate  ·  **HECHO**

**Dónde**: [supabase_db_service.dart:383-436](lib/services/supabase_db_service.dart#L383-L436).

Para un usuario con 2 carreras son 4 consultas por recarga: personales, compartidas de la carrera A, compartidas de la B, y una "red de seguridad" que vuelve a pedir todas las creadas por él. Y `loadTasks()` se dispara con cada evento de Realtime.

La política `shared_tasks_select` ya filtra por membresía, así que el bucle está reimplementando en el cliente lo que el servidor hace mejor.

**Qué haría**: una sola consulta `from('shared_tasks').select()`, sin filtros de carrera. RLS devuelve exactamente lo que corresponde, incluidas las propias — con lo que la consulta de rescate también sobra. De 4 consultas a 2, y menos código.

**Esfuerzo**: S.

---

### 1.5 — Una búsqueda DNS a Google en cada recarga  ·  **HECHO**

**Dónde**: [local_cache_service.dart:55-69](lib/services/local_cache_service.dart#L55-L69).

`hasConnection()` resuelve `google.com` con 3 segundos de tiempo límite. La llama `forceSync()`, que llama `loadTasks()`, que se dispara con cada evento de Realtime y con cada `notifyListeners()` de `CareerService`.

Sin conexión eso son 3 segundos de bloqueo por recarga. Con conexión, una consulta DNS a un tercero cada vez que cambia algo.

**Qué haría**: guardar el último estado conocido, actualizarlo desde el stream de `connectivity_plus` (que ya está suscrito), y limitar la verificación activa a una vez por minuto como máximo.

**Esfuerzo**: S.

---

### 1.6 — El progreso se aplica dos veces  ·  **HECHO**

**Dónde**: [supabase_db_service.dart:466](lib/services/supabase_db_service.dart#L466) devuelve `applyCurrentUserProgress(tasks)`, y [app_state.dart:121-129](lib/providers/app_state.dart#L121-L129) vuelve a mapear el mismo progreso sobre el resultado.

Hoy es inofensivo porque las dos pasadas leen la misma caja de Hive. Es un duplicado esperando a divergir. Quitar el segundo.

**Esfuerzo**: S.

---

### 1.7 — Colisiones posibles en los ids de notificación  ·  **HECHO**

**Dónde**: [notification_service.dart:36-52](lib/notification_service.dart#L36-L52).

El id se calcula hasheando los **últimos 8 caracteres** del id de la tarea, y el aviso de 2 horas usa `baseId + 1000000`. Nada impide que ese valor coincida con el `baseId` de otra tarea, en cuyo caso una cancela o pisa el recordatorio de la otra.

Baja probabilidad, pero el fallo es silencioso y el síntoma ("a veces no me avisa") es imposible de diagnosticar.

**Qué haría**: hashear el id completo y separar los espacios por rango en vez de por suma (por ejemplo, `hash % 500000000` para el de 24 h y `+ 1000000000` para el de 2 h, que no se solapan).

**Esfuerzo**: S.

---

### 1.8 — Fuga de listener en `AppState`  ·  **HECHO**

**Dónde**: [app_state.dart:50-54](lib/providers/app_state.dart#L50-L54) registra un listener en el singleton `CareerService`; [:354](lib/providers/app_state.dart#L354) `dispose()` no lo quita.

En producción hay una sola instancia de `AppState`, así que no se nota. En pruebas de widget y en hot reload sí: quedan `AppState` muertos recibiendo notificaciones. Guardar la referencia al closure y hacer `removeListener` en `dispose`.

**Esfuerzo**: S.

---

## Prioridad 2 — Seguridad y privacidad

### 2.1 — Compartir un archivo lo vuelve público sin decirlo  ·  **HECHO**

**Dónde**: [area_personal_screen.dart:402](lib/screens/area_personal_screen.dart#L402) y [:423](lib/screens/area_personal_screen.dart#L423), que llaman a [`makeFilePubliclySharable`](lib/services/google_drive_service.dart#L313) — un permiso `{'role': 'reader', 'type': 'anyone'}`.

"Copiar enlace" y "Enviar a…" dicen *"Comparte el enlace de este archivo"*. Lo que realmente ocurre es que el archivo del Drive personal del estudiante pasa a ser legible por cualquiera que tenga el enlace, para siempre, y el cambio no se revierte ni se puede deshacer desde la app.

En una app cuya promesa es que los archivos son privados de quien los sube, esto contradice la expectativa del usuario.

**Resuelto quitando la función, no advirtiéndola.** Se eliminaron el botón de compartir, el bottom sheet completo ("Copiar enlace" y "Enviar a…") y los métodos `makeFilePubliclySharable` / `revokePublicAccess` de `GoogleDriveService`.

El motivo de fondo no es que compartir fuera peligroso, sino que sobraba: abrir un archivo lleva a la interfaz de Google Drive, que ya trae compartir, permisos, descargar y enviar, mejor resueltos que cualquier reimplementación nuestra. Bitácora organiza los archivos; repartirlos es trabajo de Drive. Una función menos, una superficie de privacidad menos y ~126 líneas menos.

**Nota**: los archivos que se compartieron con la versión anterior **siguen públicos en Drive**. La app ya no puede revertirlo — hay que quitar el acceso desde Drive (botón Compartir → quitar "Cualquier persona con el enlace").

---

### 2.2 — Contraseña maestra compilada en cada APK  ·  **HECHO**

**Dónde**: [admin_auth_service.dart:30](lib/services/admin_auth_service.dart#L30).

Un SHA-256 sin sal de una contraseña compartida, dentro del binario. Se extrae del APK y se rompe fuera de línea; el límite de 5 intentos solo estorba dentro de la app.

El daño real está acotado, y eso hay que decirlo: las escrituras las protege `careers_admin_write` con `public.is_admin()`, columna que el usuario no puede modificar. Quien rompa la contraseña ve el panel y no puede guardar nada.

Aun así es un secreto compartido que hay que rotar a mano cada vez que se filtra — ya pasó una vez, en mayo de 2026.

**Resuelto borrándolo.** `AdminAuthService` pasó de 142 líneas a 41: ya no hay hash, ni contador de intentos, ni bloqueo de 15 minutos. La única pregunta es `public.is_admin()`, la misma función que ya usaban las políticas RLS de escritura, así que el permiso real no cambió — cambió cómo se decide qué mostrar.

La entrada al panel dejó de ser una contraseña escondida en el campo de clave de acceso y pasó a ser una tarjeta visible, en Configuración → Cuenta y en la pantalla de selección de carrera, solo para quien corresponde.

La columna `admin_password_hash` se borró en `supabase_hardening_12_sin_contrasena_maestra.sql`, **ya aplicado en producción**.

**Efecto en cuentas existentes**: una sola cuenta tiene `is_admin = true`. Quien tuviera una contraseña personal guardada y no ese flag pierde el acceso al panel — que igual no le servía de nada, porque las políticas RLS le rechazaban toda escritura.

No queda ningún secreto compartido que rotar.

---

### 2.3 — En web el token de Drive no está en un llavero del sistema  ·  **HECHO**

`flutter_secure_storage` en web no tiene Keystore ni Keychain detrás: cae a almacenamiento del navegador, o sea que el token de Google quedaba escrito en el disco del equipo y sobrevivía al cierre de la pestaña.

**Resuelto no persistiéndolo en web.** El token vive en memoria y muere al recargar la página. El costo es mínimo: Supabase devuelve un `providerToken` con la sesión y, si no lo hay, GIS abre el popup. En un computador compartido es exactamente el comportamiento que se quiere.

En Android e iOS no cambia nada: ahí sí hay Keystore/Keychain detrás.

---

### 2.4 — Limpiezas pendientes del endurecimiento  ·  **HECHO**

- Borrar la columna `careers.access_key`, obsoleta desde la migración 2 y marcada para la fase 3.
- Borrar la tabla `active_sessions`, que ningún código toca (ver 3.2).

Escrito en `supabase_hardening_10_limpieza.sql` y reflejado en `supabase_schema.sql`. **Falta ejecutarlo en el SQL Editor** — borra datos, así que se corre cuando tú digas.

**Esfuerzo**: S.

---

## Prioridad 3 — Arquitectura y mantenibilidad

### 3.1 — `area_personal_screen.dart` tiene 1563 líneas  ·  **PARCIAL**

Es el archivo más grande del proyecto con diferencia. Dentro: tres pestañas, el flujo de subida, la sincronización con Drive, cuatro diálogos y dos constructores de tarjeta. Cada cambio ahí obliga a releer todo.

**Hecho hasta ahora**: 1503 → 1136 líneas, quitando lo que estaba duplicado, que era el objetivo real:

- `lib/widgets/career_subject_picker.dart` — el par carrera → asignatura en cascada, que estaba copiado **tres** veces (subir archivo, editar archivo, agregar enlace), cada copia con su propia lista de materias y su propio `onChanged` recalculando lo mismo.
- `lib/widgets/study_file_card.dart` — un solo constructor de tarjeta en vez de dos casi idénticos que solo diferían en la etiqueta y el subtítulo.

Con el picker se fueron además dos `StatefulBuilder` que existían solo para redibujar los desplegables.

**Falta**: separar las pestañas en `files_tab.dart` y `teaching_materials_tab.dart`. Es mecánico pero pasa por inyectar media docena de callbacks, y conviene hacerlo con la app compilable y probada a mano.

**Esfuerzo**: M. Sin cambio de comportamiento, por lo que es seguro hacerlo antes que el resto.

---

### 3.2 — Código muerto: ~350 líneas y una tabla  ·  **HECHO**

| Qué | Tamaño | Decisión | Estado |
|---|---|---|---|
| `DataExportService` | 208 líneas | Borrar (ver 4.4) | **hecho** — con él salieron `share_plus` y `path_provider` |
| `SessionControlService` + tabla `active_sessions` | 78 líneas | Borrar | **hecho** — código borrado; la tabla, en la migración 10 |
| `Meeting.isCompleted` | 1 campo | Conectarlo (ver 4.3) | **hecho** |
| `getPublicSubjects`, `searchTasks`, `getTasksBySubject`, `uniqueSubjects`, `watchProgress` | ~40 líneas | Borrar | **hecho** |
| `Task.collaborators` | 1 campo | Decidir: no hay pantalla ni política que lo use | pendiente |

Cada línea muerta se lee, se mantiene y confunde a quien busca cómo funciona algo.

**Esfuerzo**: S.

---

### 3.3 — Los servicios no tienen ni una prueba

60 pruebas, todas sobre modelos y utilidades puras. Cero sobre `SyncService`, `TaskProgressService`, `CareerService`, `MeetingService`, `StudyFileService` y `SupabaseDbService` — que es exactamente donde han estado todos los errores de las últimas cinco versiones.

Tres archivos son cascarones de la migración desde Firebase: `sync_service_test.dart`, `task_progress_service_test.dart` e `integration_test.dart`, los tres con `void main() {}`.

**Qué haría**, empezando por lo que más se rompe:

1. `SyncService`: cola con fallos parciales, no perder items, no duplicar creaciones. Ya existe `SyncService.test()` con inyección de dependencias, así que no hay que rediseñar nada.
2. `TaskProgressService`: reconciliación por `updatedAt` en las dos direcciones.
3. `MeetingService.getMeetings`: filtros de carrera y membresía, `effectiveDate` de recurrentes alrededor de la hora de corte.
4. `CareerService`: migración del formato antiguo, `matchesAnyCareer`, entrada y salida de carreras.

De paso: `CLAUDE.md` documenta `flutter test integration_test/` y ese directorio no existe. Corregirlo o crearlo.

**Esfuerzo**: M por servicio.

---

### 3.4 — Dos formatos de serialización para el mismo modelo  ·  **PARCIAL**

`Task.toMap()` usa `camelCase` (`dueDate`, `isCompleted`) para Hive; `_taskToRow()` usa `snake_case` (`due_date`, `is_completed`) para Supabase.

La ficha original decía que `fromMap` adivinaba cuál le llegaba. Revisándolo, no: había **dos lectores paralelos** —`Task.fromMap` para la caché y `_rowToTask` para el servidor— con los mismos campos escritos dos veces y valores por defecto que ya habían empezado a divergir (uno decía `'Sin título'`, el otro `'Tarea sin título'`).

**Hecho**: un solo lector. `Task.fromMap` entiende los dos formatos y `_rowToTask` quedó en una línea que lo llama. Cubierto por `test/task_from_map_test.dart` (8 pruebas), porque ahora es el punto por el que pasa *todo* lo que la app lee.

**Falta**: unificar también la escritura. Eso sí cambia el formato guardado en Hive, o sea que toda caché existente dejaría de parsearse — incluidas las tareas creadas sin conexión y aún no subidas. No es un cambio para hacer sin poder probar la app en un teléfono.

---

### 3.5 — Tres nociones de "carrera" conviviendo

`CareerService` (local, Hive), `CareerSupabaseService` (remoto) y la clase estática `Careers` con una lista **mutable** `Careers.remote` que cualquiera puede reescribir. Estado global mutable, imposible de probar en aislamiento, y la causa de que `getCareers()` tenga que resolver cada carrera contra `Careers.findById` en cada lectura.

Depende de 1.1: si `user_careers` pasa a ser la fuente de verdad, este enredo se simplifica solo. Hacerlos juntos.

**Esfuerzo**: M.

---

### 3.6 — Comentarios y documentación desfasados  ·  **HECHO**

- [sync_service.dart:56](lib/services/sync_service.dart#L56): *"connectivity_plus v5+ emite List<ConnectivityResult>"* — el código maneja un valor único, que es lo correcto en la v5 que usa el proyecto. El comentario dice lo contrario de lo que hace el código.
- `local_cache_service.dart` y `career_model.dart:117` siguen hablando de Firebase y Firestore.
- `ErrorMessages.fromFirebaseError` se llama en todas las pantallas y ya no hay Firebase.
- [config_screen.dart:374](lib/screens/config_screen.dart#L374) muestra **"Versión 1.0.0"** en el diálogo "Acerca de". La real es 2.7.1. Es el único número de versión que ve el usuario, y lleva 6 versiones mintiendo.

**Esfuerzo**: S. La versión, con `package_info_plus` o una constante única leída del `pubspec`.

---

### 3.7 — Dependencias muy atrasadas  ·  **NO HECHO A PROPÓSITO**

Subir `flutter_local_notifications` de la 17 a la 19 es un cambio con rupturas, y este mismo ciclo reescribió el servicio de notificaciones entero. Hacer las dos cosas a la vez, sin poder instalar un APK y ver si una alarma programada suena en release, es la forma más rápida de no saber cuál de los dos cambios rompió qué. Queda para después de probar lo de ahora en el teléfono.


`flutter pub outdated` reporta 81 paquetes con versiones más nuevas incompatibles con las restricciones actuales. El que más importa:

- **`flutter_local_notifications ^17.2.3`** → la v19 trae de fábrica las reglas ProGuard de GSON que hubo que escribir a mano en la v2.7.0.
- `share_plus 7.2.2` → 13.x, `connectivity_plus 5.0.2` → 6.x (cambia la firma de `onConnectivityChanged` a `List`, ojo con 3.6), `supabase_flutter 2.16` → 2.17.

**Qué haría**: subir de a un paquete, empezando por notificaciones, con una prueba manual de recordatorio programado en release después de cada uno.

**Esfuerzo**: M.

---

## Prioridad 4 — Experiencia de uso

### 4.1 — "Mis tareas" no son tareas  ·  **HECHO**

La pestaña **Mis tareas** de Mi área contiene **archivos**. Las tareas de verdad están en Pendientes, Vencidas y Entregadas. Dos cosas distintas con el mismo nombre, a un toque de distancia.

**Qué haría**: renombrar la pestaña a **Mis archivos** o **Mis trabajos**. Cambio de una línea con el mayor retorno de todo este documento.

**Esfuerzo**: S.

---

### 4.2 — No se puede editar una tarea vencida sin moverle la fecha  ·  **HECHO**

**Dónde**: [add_task_screen.dart:449](lib/screens/add_task_screen.dart#L449) — `firstDate: DateTime.now()`.

Al editar una tarea ya vencida, el selector no deja elegir su fecha original. Corregir una descripción obliga a inventar una fecha futura, y la tarea salta de Vencidas a Pendientes.

**Qué haría**: `firstDate: task?.dueDate.isBefore(now) == true ? task!.dueDate : now`.

**Esfuerzo**: S.

---

### 4.3 — Las reuniones no se pueden marcar como hechas  ·  **HECHO**

El campo existe en el modelo y en la tabla desde el principio. Falta el interruptor. Para una reunión no recurrente sería el equivalente a "entregada" en las tareas y evitaría que ocupe el tope de la lista hasta que la purga de 7 días la borre.

**Esfuerzo**: S.

---

### 4.4 — No hay copia de seguridad ni salida de datos  ·  **HECHO (borrado)**

`DataExportService` hace exactamente esto y nadie lo llama. Para una app donde un estudiante acumula un semestre de trabajo, poder llevarse los datos no es un lujo.

**Se borró.** Las razones para no revivirlo: exportaba también las tareas compartidas de la carrera, o sea trabajo de otras personas; el "importar" era un cuadro para pegar JSON a mano que nadie iba a usar; y estaba escrito para el modelo de datos de Firebase. Los datos ya viven en Supabase y los archivos en el Drive del usuario, así que la pérdida real es poco probable.

Con él salieron las dependencias `share_plus` y `path_provider`, que no usaba nadie más desde que se quitó el compartir de archivos.

Si algún día se quiere exportar datos, se escribe de cero con el filtro correcto y un selector de archivo de verdad.

---

### 4.5 — Búsqueda solo en Pendientes  ·  **HECHO**

Vencidas y Entregadas no tienen buscador, y son justo donde se acumulan las tareas: buscar "el ensayo de Hermenéutica del semestre pasado" no es posible.

Además, el diálogo de búsqueda de Pendientes construye un `TextEditingController` dentro del `builder` ([pending_tasks_screen.dart:264](lib/screens/pending_tasks_screen.dart#L264)) que nunca se libera, y su icono de limpiar no se actualiza porque el diálogo está en otra ruta.

**Hecho**: `lib/widgets/task_search_dialog.dart`, usado por las tres pantallas. Vencidas —donde se acumula el semestre entero y donde más falta hacía— ya tiene buscador, con su propio estado vacío y un botón para limpiar el filtro.

El controlador ahora vive en un StatefulWidget que lo libera. Antes se construía dentro del `builder` del diálogo en Pendientes y en Entregadas: se recreaba en cada reconstrucción, nunca se liberaba y perdía la posición del cursor.

El filtro pasó a ser una sola función (`TaskSearchDialog.matches`), probada, y de paso busca también por profesor. Y ya no filtra en vivo detrás del modal, donde el usuario no podía ver el resultado igual.

---

### 4.6 — Los tipos de tarea no coinciden entre formulario y modelo  ·  **HECHO**

El formulario ofrece 9 tipos; el modelo acepta 11 (`laboratorio` y `presentacion` sin tilde están de más). Una tarea creada en otra versión con `laboratorio` es válida pero no seleccionable al editarla. Unificar en una sola lista, en el modelo.

**Esfuerzo**: S.

---

### 4.7 — Reprogramación de recordatorios en cada recarga

`syncAllTaskReminders` recorre **todas** las tareas y, por cada una, llama al plugin de notificaciones. Con Realtime disparando `loadTasks()` en cada cambio, son cientos de llamadas al canal nativo por sesión.

Mejoró a medias con 5.1: ahora es **una** llamada por tarea en vez de dos, y una sola lectura de `SharedPreferences` por pasada en vez de dos por tarea. Sigue faltando reprogramar solo lo que cambió.

**Qué haría**: comparar contra lo ya programado y tocar únicamente las tareas cuya fecha o estado cambió.

**Esfuerzo**: M.

---

## 5. Notificaciones

### 5.1 — Cuatro avisos y un solo interruptor  ·  **HECHO**

**Dónde**: [notification_service.dart](lib/notification_service.dart), [config_screen.dart](lib/screens/config_screen.dart).

Antes había tres preferencias separadas (24 h, 2 h, reuniones) y cinco avisos distintos entre tareas y reuniones. El usuario tenía que entender la diferencia entre "aviso 24 h" y "aviso de reuniones" para apagar algo que en su cabeza era una sola cosa. Ahora:

| Aviso | Cuándo |
|---|---|
| Resumen del día | 8:00, *"Hoy tienes 3 reuniones y 2 tareas con fecha límite"* |
| Tarea | 2 h antes del vencimiento |
| Reunión | 5 min antes de su hora |
| Tarea compartida | cuando otra persona la crea o la edita |

Todo cuelga de un interruptor único y de **un solo canal de Android**, para que el usuario no pueda silenciar un canal sin darse cuenta y creer que la app está rota.

Detalles que valen la pena:

- El resumen no puede ser una repetición diaria con texto fijo, porque los números cambian cada día. Se dejan programados los próximos 7 días, cada uno con sus propias cuentas, y un día sin nada agendado no suena.
- Las reuniones semanales usan repetición nativa (`dayOfWeekAndTime`): siguen avisando aunque la app no se abra en meses.
- Se separaron los rangos de ids de tareas y reuniones. Antes salían del mismo hash y del mismo rango, así que dos podían colisionar y una cancelaba el aviso de la otra (era el resto del problema 1.7).

**Límite conocido**: el aviso de tarea compartida nace de la suscripción Realtime, no de un push del servidor. Llega solo mientras el proceso de la app siga vivo; con la app cerrada por el sistema no hay nada escuchando. Que llegara siempre exige FCM y una función en el servidor que lo dispare — ver 5.2.

---

### 5.2 — Push real para cambios del grupo

Hoy no hay Firebase Cloud Messaging en el proyecto. Mientras no lo haya, ningún aviso originado en el servidor (alguien creó una tarea, alguien cambió una fecha) puede llegar con la app cerrada.

**Qué haría**: `firebase_messaging` en el cliente y un trigger en Supabase que llame a la API de FCM al insertar o actualizar en `shared_tasks`, con los tokens de los miembros de la carrera guardados en una tabla nueva.

**Esfuerzo**: L. Implica cuenta de servicio de Firebase, un secreto en el servidor y manejo de tokens caducados.

---

## Orden sugerido

Si hay que elegir, esta secuencia da el mayor retorno por esfuerzo y deja cada paso apoyado en el anterior:

~~Primera tanda~~, ~~segunda tanda~~ y ~~1.1~~ están hechas. Lo que queda:

~~2.2~~, ~~2.3~~, ~~4.5~~, ~~4.7~~ y ~~5.1~~ están hechas; 3.1, 3.3 y 3.4 a medias. Lo que queda:

**Siguiente, y todo pasa por lo mismo**: probar en un teléfono lo de este ciclo. Después vienen 3.7 (subir dependencias, empezando por notificaciones) y la otra mitad de 3.4 (unificar la escritura, que cambia el formato de la caché de Hive).

**Después.** 3.5 (unificar las tres nociones de carrera), el resto de 3.1 (separar las pestañas), más pruebas de servicios (3.3) y 5.2 (push real con FCM, que necesita cuenta de servicio de Firebase).
