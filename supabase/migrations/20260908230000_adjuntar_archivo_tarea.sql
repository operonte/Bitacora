-- Bitácora — adjuntar un archivo existente a una tarea.
--
-- Sin FK: una tarea puede estar en `tasks` (privada) o en `shared_tasks`
-- (compartida), y una columna no puede apuntar a dos tablas a la vez. Mismo
-- criterio que career_id en esta misma tabla — es una etiqueta para
-- relacionar, no algo que decida quién ve el archivo: eso lo sigue
-- resolviendo study_files_own como siempre.

BEGIN;

ALTER TABLE public.study_files
  ADD COLUMN IF NOT EXISTS task_id TEXT;

CREATE INDEX IF NOT EXISTS idx_study_files_task_id
  ON public.study_files(task_id) WHERE task_id IS NOT NULL;

COMMIT;
