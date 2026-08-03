-- ============================================================
-- BITÁCORA — Material docente unificado con los archivos de estudio
--
-- "Mis tareas" (trabajos subidos) y "Material docente" (guías) son lo mismo
-- con distinta categoría, así que comparten tabla en vez de mantener dos
-- implementaciones paralelas. La tabla teaching_materials nunca llegó a
-- existir —jamás tuvo DDL en el repo— y por eso las subidas de material
-- docente fallaban después de haber subido el archivo a Drive.
--
-- Al pasar a ser privado (solo lo ve quien lo sube), career_id y user_name
-- dejan de tener sentido: la política study_files_own ya cubre ambas
-- categorías y no hace falta tocar RLS.
--
-- Ejecutar en el SQL Editor. Idempotente.
-- ============================================================

ALTER TABLE public.study_files
  ADD COLUMN IF NOT EXISTS category     TEXT NOT NULL DEFAULT 'trabajo',
  ADD COLUMN IF NOT EXISTS description  TEXT,
  ADD COLUMN IF NOT EXISTS external_url TEXT;

-- ADD CONSTRAINT no admite IF NOT EXISTS, de ahí la guarda.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'study_files_category_chk'
  ) THEN
    ALTER TABLE public.study_files
      ADD CONSTRAINT study_files_category_chk
      CHECK (category IN ('trabajo', 'guia'));
  END IF;
END $$;

-- Un material puede ser un enlace externo, que no tiene archivo en Drive.
ALTER TABLE public.study_files ALTER COLUMN drive_file_id DROP NOT NULL;
ALTER TABLE public.study_files ALTER COLUMN mime_type     DROP NOT NULL;
ALTER TABLE public.study_files ALTER COLUMN size_bytes    DROP NOT NULL;

CREATE INDEX IF NOT EXISTS idx_study_files_user_category
  ON public.study_files(user_id, category);

-- La tabla teaching_materials nunca existió en el repo. Si alguien la creó a
-- mano en el dashboard, esto rescata sus filas antes de que queden huérfanas.
DO $$
BEGIN
  IF to_regclass('public.teaching_materials') IS NOT NULL THEN
    INSERT INTO public.study_files (
      id, name, subject, drive_file_id, mime_type, size_bytes, drive_link,
      user_id, created_at, category, description, external_url
    )
    SELECT t.id, t.title, t.subject, t.drive_file_id, t.mime_type,
           t.size_bytes, COALESCE(t.drive_link, ''), t.user_id,
           NOW(), 'guia', t.description, t.external_url
    FROM   public.teaching_materials t
    ON CONFLICT (id) DO NOTHING;

    RAISE NOTICE 'Filas migradas desde teaching_materials. Revisa y luego: DROP TABLE public.teaching_materials;';
  END IF;
END $$;

-- ─── VERIFICACIÓN ────────────────────────────────────────────
SELECT column_name, data_type, is_nullable, column_default
FROM   information_schema.columns
WHERE  table_schema = 'public' AND table_name = 'study_files'
ORDER  BY ordinal_position;
