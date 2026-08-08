-- ============================================================
-- BITÁCORA — Carrera en los archivos de estudio (filtro)
--
-- study_files perdió career_id en la migración 7, cuando el material docente
-- pasó a ser privado: como ya no definía quién veía qué, dejó de tener
-- sentido. Ahora vuelve, pero con otro propósito: poder filtrar "Mis tareas"
-- y "Material docente" por carrera, igual que se hace en las reuniones.
--
-- IMPORTANTE: esto NO cambia la visibilidad. Los archivos siguen siendo
-- privados de quien los sube — la política study_files_own (auth.uid() =
-- user_id) no se toca. career_id es solo una etiqueta para agrupar.
--
-- Los archivos ya subidos quedan con career_id NULL y aparecen como
-- "Sin carrera" hasta que se editen. No se intenta adivinar la carrera a
-- partir de la materia: dos carreras pueden compartir el nombre de una
-- materia y quedaría mal clasificado en silencio.
--
-- Ejecutar en el SQL Editor. Idempotente.
-- ============================================================

ALTER TABLE public.study_files
  ADD COLUMN IF NOT EXISTS career_id TEXT;

-- El filtro consulta siempre acotado al dueño, de ahí el índice compuesto.
CREATE INDEX IF NOT EXISTS idx_study_files_user_career
  ON public.study_files(user_id, career_id);

-- ─── VERIFICACIÓN ────────────────────────────────────────────
SELECT column_name, data_type, is_nullable, column_default
FROM   information_schema.columns
WHERE  table_schema = 'public' AND table_name = 'study_files'
ORDER  BY ordinal_position;
