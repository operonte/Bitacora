-- ============================================================
-- BITÁCORA — Índices que el esquema documentaba pero no existían
--
-- supabase_schema.sql tenía una sección "ÍNDICES B-TREE DE SEGURIDAD Y
-- RENDIMIENTO" que nunca se ejecutó. Comprobado contra producción con
-- `supabase db dump`: de los diez índices declarados solo existen tres
-- (idx_meetings_career_shared, idx_study_files_user_category e
-- idx_study_files_user_career).
--
-- NO ES URGENTE, y conviene decirlo: hoy las tablas son diminutas (5 carreras,
-- 27 archivos, 13 reuniones, 6 membresías), así que un recorrido secuencial
-- cuesta lo mismo que un índice. Esto es prevención para cuando crezca, y
-- sobre todo para que el esquema del repo deje de describir una base que no
-- es la real.
--
-- Solo se crean los que alguna consulta usa de verdad:
--
--   tasks(user_id)            → getTasks filtra por dueño; la PK es (id)
--   shared_tasks(career_id)   → lo usa la subconsulta de shared_tasks_member
--   shared_tasks(created_by)  → la otra rama de esa misma política
--   meetings(user_id)         → meetings_select; el índice que hay es parcial
--                               sobre career_id y no cubre esta rama
--   subjects(user_id)         → getSubjects filtra por dueño
--
-- Deliberadamente NO se crean:
--   user_careers  → su PK (user_id, career_id) ya cubre las búsquedas de RLS
--   task_progress → su PK (user_id, task_id) ya cubre las suyas
--   study_files   → idx_study_files_user_category y _user_career empiezan por
--                   user_id, así que ya sirven para filtrar por dueño
--
-- Ejecutar en el SQL Editor. Idempotente y no destructivo.
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_tasks_user_id
  ON public.tasks(user_id);

CREATE INDEX IF NOT EXISTS idx_shared_tasks_career_id
  ON public.shared_tasks(career_id);

CREATE INDEX IF NOT EXISTS idx_shared_tasks_created_by
  ON public.shared_tasks(created_by);

CREATE INDEX IF NOT EXISTS idx_meetings_user_id
  ON public.meetings(user_id);

CREATE INDEX IF NOT EXISTS idx_subjects_user_id
  ON public.subjects(user_id);

-- ─── VERIFICACIÓN ────────────────────────────────────────────
-- Espera ocho filas: las tres que ya existían más las cinco nuevas.
SELECT tablename, indexname
FROM   pg_indexes
WHERE  schemaname = 'public'
  AND  indexname LIKE 'idx_%'
ORDER  BY tablename, indexname;
