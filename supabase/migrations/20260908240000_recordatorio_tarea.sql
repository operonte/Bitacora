-- Bitácora — recordatorio configurable por tarea.
--
-- Mismo criterio que 20260908210000_recordatorio_reunion.sql: el aviso de
-- tarea avisaba siempre 2 horas antes, fijo para todas. NULL sigue
-- significando "usar el default de la app", así que las tareas ya creadas
-- no cambian de comportamiento. Se agrega en las dos tablas porque una tarea
-- puede vivir en cualquiera de las dos según esté compartida o no.

BEGIN;

ALTER TABLE public.tasks
  ADD COLUMN IF NOT EXISTS reminder_minutes INTEGER;

ALTER TABLE public.shared_tasks
  ADD COLUMN IF NOT EXISTS reminder_minutes INTEGER;

COMMIT;
