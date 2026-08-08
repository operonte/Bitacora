# Bitácora — Funcionalidades

Estado del código a **v2.7.1 + mejoras en curso** (base: commit `e0b7490`, 8 de agosto de 2026).

> Los cambios de la tanda de mejoras están aplicados en el árbol de trabajo pero **sin compilar ni commitear**. Ver [PLAN_DE_MEJORAS.md](PLAN_DE_MEJORAS.md).

Este documento describe lo que la app **hace hoy**, no lo que debería hacer. Cuando algo existe a medias o está en el código pero no es alcanzable desde la interfaz, se dice explícitamente.

---

## 1. Qué es

App Flutter de gestión académica para estudiantes universitarios, con soporte offline y sincronización automática. Textos e identificadores en español.

- **Plataformas compiladas**: Android (APK en GitHub Releases), Web (Firebase Hosting, `bitacora-2d643.web.app`), Linux. iOS está declarado pero sin build en el flujo actual.
- **Backend**: Supabase (PostgreSQL + RLS + Realtime + Auth). Firebase se usa **solo** como hosting de la versión web; la migración desde Firestore ya ocurrió y quedan restos de nombres en comentarios.
- **Almacenamiento de archivos**: Google Drive del propio usuario, no un bucket de la app.
- **Caché local**: Hive, cifrado con AES-256.

---

## 2. Cuentas y sesión

- **Único método de acceso: Google**. No hay registro con correo y contraseña.
  - Android: login nativo (`google_sign_in`) sin abrir navegador. Antes de iniciar se hace `signOut()` de Google para forzar el selector de cuenta.
  - Web: OAuth con `prompt=select_account`.
- Los ámbitos pedidos son `email`, `profile` y `drive.file` — este último limita el acceso a los archivos que la propia app crea, no a todo el Drive.
- **Perfil editable** desde Configuración: nombre visible y URL de foto (se guardan en los metadatos del usuario de Supabase).
- **Cerrar sesión** limpia: caché de tareas/materias/metadatos, caja de archivos, caja de reuniones, token de Drive y la sesión nativa de Google.

**Límite de sesiones simultáneas**: no existe. Había un `SessionControlService` (máximo 4 dispositivos) y una tabla `active_sessions` que ningún código llamaba; ambos se eliminaron.

---

## 3. Carreras (el eje de todo lo compartido)

Una carrera es a la vez un plan de estudios y un grupo de personas. Es el mecanismo por el que dos usuarios ven lo mismo.

- Un usuario puede pertenecer a **varias carreras a la vez**. Una de ellas es la **activa**: da el título de las pantallas y es el destino por defecto de las tareas nuevas.
- Para entrar a una carrera hay que escribir su **clave de acceso**. La clave nunca viaja dentro de la app: se guarda hasheada en `career_access_keys` y se valida en el servidor con el RPC `join_career`, que es el único que puede crear la membresía en `user_careers`.
- Salir de una carrera borra la membresía local **y** la fila en `user_careers`, que es lo que realmente revoca el acceso por RLS.
- Hay una carrera predefinida en código (`teologia`, con 8 asignaturas y sus profesores) más todas las creadas desde el panel de administración, que se cargan desde Supabase y tienen prioridad sobre la predefinida si comparten `id`.

**La lista del servidor manda.** Al arrancar y al iniciar sesión, la app compara sus carreras con `user_careers` y se ajusta: quita las que el servidor no reconoce y agrega las que sí (por ejemplo, si entraste desde otro dispositivo). Si no hay conexión no toca nada, porque no se puede distinguir "no eres miembro" de "no pude preguntar". Cuando se quita una carrera, la pantalla de clave explica cuál y por qué.

---

## 4. Tareas

### Personales vs. compartidas

La distinción la hace un solo campo:

| `careerId` | Tabla | Quién la ve |
|---|---|---|
| vacío o nulo | `tasks` | solo el creador |
| con valor | `shared_tasks` | todos los miembros de esa carrera |

Toda tarea creada con una carrera activa es compartida. No hay opción de "privada dentro de una carrera" para tareas (sí la hay para reuniones).

### Progreso personal

En una tarea compartida, "realizada" y "enviada" **no son globales**: cada miembro tiene su propio estado en la tabla `task_progress`, reconciliado por `updated_at` (gana la escritura más reciente). Así, que un compañero marque una tarea como entregada no la mueve de pantalla en tu teléfono.

### Autoría

- `user_id` / `user_name` identifican a quien **creó** la tarea y no se tocan al editar.
- En tareas compartidas, `updated_by_name` y `updated_at` los estampa el trigger `shared_tasks_stamp_author` en el servidor, no el cliente — para que nadie pueda atribuirle una edición a otra persona.

### Campos y validación

Título (3–100), descripción (hasta 1500 en el formulario, 2000 en el modelo), asignatura, profesor, tipo, fecha y hora de entrega, etiqueta opcional, colaboradores. El modelo rechaza títulos vacíos, fechas de más de 5 años atrás y tipos fuera de una lista blanca.

Tipos ofrecidos en el formulario: trabajo, resumen, estudio, prueba, examen, lectura, ensayo, presentación, otro.

### Las tres pantallas

Se derivan de la misma lista, filtradas por carrera a la que el usuario pertenece:

- **Pendientes** — no entregadas y con fecha futura. Orden: la más próxima primero.
- **Vencidas** — no entregadas y con fecha pasada. Orden: la más reciente primero.
- **Entregadas** — completadas *y* enviadas.

Una tarea marcada "realizada pero no enviada" se destaca en amarillo y no sale de Pendientes.

**Filtros y búsqueda**: chips horizontales por asignatura y un diálogo de búsqueda por título, descripción y asignatura. Solo en Pendientes.

---

## 5. Materias

Dos orígenes conviven:

1. **Predefinidas de la carrera** — vienen del código o del panel de administración, con su profesor. Son las que se autocompletan al escribir una asignatura en una tarea nueva.
2. **Propias del usuario** — creadas en "Mis Materias", con nombre, profesor, descripción y una **visibilidad** (`soloYo`, `cursoCompleto`, `seleccionar`). Las políticas RLS respetan esa visibilidad en la lectura.

Al elegir una asignatura en el formulario de tarea, el profesor se rellena solo.

---

## 6. Reuniones

Agenda de clases virtuales o presenciales, en la pestaña "Mis reuniones" de Mi área.

- Campos: título, descripción, asignatura, profesor, fecha y hora, tipo (Zoom / Google Meet / Microsoft Teams / Presencial / Otro), enlace, carrera.
- **El tipo se autodetecta del enlace**: si la URL contiene `zoom.us`, `meet.google.com` o `teams.microsoft.com`, el tipo mostrado se corrige solo.
- **Privadas o compartidas**: por defecto privada. Compartida significa visible para los miembros de la carrera elegida — una reunión compartida obliga a tener carrera. Solo el dueño puede editarla o borrarla; el resto la ve sin botones.
- **Recurrencia semanal**: una reunión marcada como recurrente recalcula su próxima ocurrencia sola. El salto a la semana siguiente ocurre a las 23:00 de su propio día, no al terminar la hora de la reunión.
- **Purga automática**: las reuniones puntuales se borran 7 días después de su fecha, al arrancar la app. Es irreversible y no hay papelera.
- **Botón "Conectarse a…"** que abre el enlace, previa validación de que el esquema sea `http` o `https`.
- Filtro por carrera y buscador por título/materia/profesor. Orden: la más próxima primero.

- **Marcar como realizada**: solo en las puntuales — una recurrente vuelve sola la semana siguiente. La reunión queda tachada y atenuada.

---

## 7. Archivos y material docente

Dos pestañas que comparten tabla, servicio y flujo, distinguidas por la columna `category`:

| Pestaña | `category` | Contenido |
|---|---|---|
| Mis archivos | `trabajo` | trabajos que sube el estudiante |
| Material docente | `guia` | guías y apuntes; admite enlaces externos sin archivo |

### Subida

- Se sube al **Google Drive del propio usuario**, en `Bitácora/<Asignatura>/`. El material docente va un nivel más abajo, en `Bitácora/<Asignatura>/Material docente/`.
- Subida *resumable* en un solo request, porque el límite garantizado de la subida *multipart* de Drive son 5 MB y aquí se permiten hasta 50.
- Al subir se pide: nombre, carrera y asignatura. La lista de asignaturas queda acotada a la carrera elegida.
- **Validación de seguridad del archivo** (`FileSecurityValidator`): máximo 50 MB, no vacío, extensión en lista blanca (documentos, imágenes, audio, video), lista negra explícita de ejecutables y comprimidos, y comprobación de la cabecera de bytes.

### Sincronización con Drive

Al tirar para refrescar, además de bajar de Supabase:

- Comprueba archivo por archivo si sigue existiendo en Drive; si el usuario lo borró desde Drive, desaparece también de la app.
- Escanea `Bitácora/` y sus subcarpetas y **registra automáticamente** archivos que el usuario dejó ahí a mano. El escaneo solo baja un nivel, y de eso depende que el material docente no se registre además como trabajo.

### Otras acciones

- Editar nombre, carrera, asignatura y (en material) descripción.
- Borrar, con opción de borrar también en Drive.
- **No hay botón de compartir, y es deliberado.** Abrir un archivo lleva a la interfaz de Google Drive, que ya ofrece compartir, permisos, descargar y enviar. La app no compite con eso. El botón que existía hacía público el archivo para cualquiera con el enlace, en silencio, y se eliminó.
- Filtro por carrera y agrupación plegable por asignatura, con buscador.

**Los archivos siempre son privados de quien los sube.** La política `study_files_own` no cambió: `career_id` es solo una etiqueta para filtrar.

---

## 8. Notificaciones (solo Android)

- **Recordatorio diario** a las 08:00.
- **Por tarea**: 24 horas antes y 2 horas antes. Cada uno se puede apagar por separado.
- **Por reunión**: la mañana del día (08:00) y 2 horas antes.
- Los recordatorios se reprograman solos cada vez que cambia la lista de tareas, y se cancelan cuando la tarea se entrega o vence.

Detalles que costaron sangre y conviene no deshacer:

- La zona horaria se detecta del dispositivo. Sin eso, `timezone` asume UTC y los avisos suenan con horas de diferencia.
- Se comprueba `SCHEDULE_EXACT_ALARM` en runtime **antes** de pedir modo exacto, con caída a inexacto. Usar `AndroidScheduleMode.alarmClock` no es alternativa: el plugin lanza una `SecurityException` nativa que ningún `catch` de Dart atrapa.
- Reglas ProGuard de GSON y `keep.xml` para el ícono: sin ellas, R8 renombraba las clases que serializan la alarma y las notificaciones programadas nunca llegaban en release.

**Tarjeta de diagnóstico de permisos** en Configuración: muestra el estado real de notificaciones, alarmas exactas, exención de optimización de batería y si el canal de recordatorios quedó silenciado, con un botón "Arreglar" que lleva directo a la pantalla correcta del sistema.

---

## 9. Funcionamiento sin conexión

Patrón *offline-first* en todas las lecturas: se pinta desde Hive primero, se notifica a la interfaz, y luego se actualiza desde Supabase.

En las escrituras:

- Si la escritura remota falla, el dato se guarda en caché con un id temporal (`temp_…`) y se encola en `pending_sync`.
- `SyncService` escucha los cambios de conectividad y reintenta la cola. Los items que fallan se conservan individualmente para el siguiente intento; los que funcionaron salen de la cola.
- Excepción deliberada: una tarea **de carrera** que falla al crearse **no** se reintenta en la tabla personal. Hacerlo la volvería privada en silencio y el resto de la carrera dejaría de verla.
- Indicador de estado de sincronización en la barra superior de las tres pantallas de tareas.

Realtime: la app se suscribe a cambios en `tasks`, `shared_tasks` de sus carreras y `task_progress`, y recarga al vuelo.

---

## 10. Arranque

`main.dart`, en orden estricto: Supabase → locale `es` → Hive → **cifrado** → caché local → progreso de tareas → carreras → reuniones (+ purga de vencidas) → archivos → tema → sincronización → permisos y notificaciones (no en web).

Cualquier excepción en esa cadena se atrapa y lleva a `StartupErrorScreen` en vez de reventar.

**Recuperación de clave perdida** (v2.7.1): si el almacenamiento seguro queda ilegible — típicamente porque Android restauró una copia de seguridad de los datos sin la clave del Keystore, que nunca se respalda — se regenera la clave y se borran las cajas de Hive por nombre. Solo se pierde la caché; todo vuelve a bajarse de Supabase. Además el backup automático está desactivado (`allowBackup=false` y `data_extraction_rules.xml`), porque respaldar datos cifrados sin su clave no restaura nada útil.

---

## 11. Interfaz

- **Navegación**: 4 pestañas inferiores — Pendientes, Vencidas, Entregadas, Mi área. Mi área tiene a su vez 3 pestañas internas.
- **Temas**: claro, oscuro y seguir al sistema. Tres paletas: por defecto (teal), verde y rosa.
- **Mascota**: la paleta elige la mascota. Verde da un robot, rosa un gato, la de por defecto ninguna. Aparece flotando en la esquina y en el estado vacío de Pendientes.
- **Tipografía**: Atkinson Hyperlegible para texto corrido (pensada para lectura prolongada) y Crimson Pro serif para títulos.
- **Onboarding** al primer arranque, repetible desde Configuración.
- Listas largas agrupadas en carpetas plegables por asignatura, ordenadas por fecha, con buscador.

---

## 12. Panel de administración

Se abre escribiendo la contraseña maestra en la pantalla de selección de carrera. Permite:

- Crear, editar y borrar carreras, con su clave de acceso.
- Gestionar las asignaturas de cada carrera (nombre, profesor, descripción), en tiempo real vía stream.
- Sección Debug: enviar una notificación inmediata y programar una a 1 minuto, para aislar si el problema está en la entrega o en la alarma.

**Cómo se protege realmente**: la verificación de la contraseña corre en el cliente y es cosmética. Lo que impide escribir es la política `careers_admin_write`, que exige `public.is_admin()`, o sea la columna `profiles.is_admin` — que el propio usuario no puede modificar. Alguien que rompa la contraseña ve el panel pero no puede guardar nada.

---

## 13. Modelo de datos (Supabase)

| Tabla | Para qué | Quién puede leer |
|---|---|---|
| `profiles` | nombre, correo, foto, `is_admin` | solo el dueño |
| `careers` | catálogo de carreras y sus asignaturas | todos, incluso sin login |
| `career_access_keys` | claves hasheadas | nadie desde el cliente |
| `user_careers` | membresías | el dueño (borrar incluido) |
| `subjects` | materias personales | según `visibility` |
| `tasks` | tareas privadas | solo el dueño |
| `shared_tasks` | tareas de carrera | miembros de esa carrera |
| `task_progress` | progreso personal por tarea | solo el dueño |
| `meetings` | reuniones | el dueño, más la carrera si `is_private = false` |
| `study_files` | archivos y material | solo el dueño |

Migraciones aplicadas: `supabase_hardening.sql` y las numeradas 2 a 9. La 9 (carrera en archivos) se ejecutó el 8 de agosto de 2026.

**Pendiente de ejecutar**: `supabase_hardening_10_limpieza.sql` — borra `careers.access_key` (obsoleta desde la migración 2) y la tabla `active_sessions`. Escrita, no ejecutada.

---

## 14. Lo que está en el código pero no se puede usar

Inventario para que nadie lo confunda con funcionalidad existente:

- **`Task.collaborators`** — se guarda y se envía, pero no hay pantalla que lo edite ni política que lo use. Es lo único que queda por decidir.

Ya eliminados: `DataExportService` (y con él `share_plus` y `path_provider`), `SessionControlService`, `SupabaseDbService.getPublicSubjects()` y `registerCareerMemberships()`, `AppState.searchTasks` / `getTasksBySubject` / `uniqueSubjects`, y `TaskProgressService.watchProgress`.

---

## 15. Pruebas

60 pruebas unitarias, todas verdes. Cubren modelos (`Task`, `Subject`, `Career`, `StudyFile`), `InputSanitizer`, `FileSecurityValidator`, `LocalCacheService` y dos widgets.

No hay copia de seguridad ni exportación de datos: existía código para ello sin conectar y se eliminó.

No hay ninguna prueba de `SyncService`, `TaskProgressService`, `CareerService`, `MeetingService`, `StudyFileService` ni `SupabaseDbService`. Tres archivos (`sync_service_test.dart`, `task_progress_service_test.dart`, `integration_test.dart`) son cascarones con `void main() {}` desde la migración de Firebase a Supabase. `CLAUDE.md` documenta `flutter test integration_test/`, pero ese directorio no existe.
