-- Bitácora — study_files.user_id NOT NULL
--
-- supabase_schema.sql lo documentaba NOT NULL desde el principio, pero la
-- columna en producción no tenía la restricción (drift entre el esquema
-- documentado y el real). Con la policy study_files_own
-- (USING user_id = auth.uid()::text), una fila con user_id NULL queda
-- invisible para todo el mundo, ni su "dueño" la puede ver o borrar: no es
-- fuga de datos, pero sí basura silenciosa que nadie puede limpiar desde la
-- app.
--
-- Verificado antes de este archivo: 0 filas con user_id NULL en producción
-- (de 101 totales), así que no hace falta backfill.

ALTER TABLE public.study_files
  ALTER COLUMN user_id SET NOT NULL;
