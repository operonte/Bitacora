-- Bitácora — material docente compartido por asignatura/semestre.
--
-- Hasta ahora study_files_own dejaba cada archivo privado de quien lo sube,
-- "Material docente" incluido pese al nombre. Se agrega is_shared (solo
-- tiene sentido para category='guia') y se reparte la política por comando,
-- igual que shared_tasks: cualquiera lee lo propio y lo compartido que le
-- corresponde por can_see_shared_subject_content(); solo el dueño escribe,
-- y compartir (is_shared = true) exige ser docente de esa carrera.

BEGIN;

ALTER TABLE public.study_files
  ADD COLUMN IF NOT EXISTS is_shared BOOLEAN NOT NULL DEFAULT FALSE;

DROP POLICY IF EXISTS "study_files_own" ON public.study_files;

CREATE POLICY "study_files_select" ON public.study_files
  FOR SELECT TO authenticated USING (
    user_id = auth.uid()::text
    OR (
      is_shared
      AND category = 'guia'
      AND career_id IS NOT NULL
      AND public.can_see_shared_subject_content(career_id, subject)
    )
  );

CREATE POLICY "study_files_insert" ON public.study_files
  FOR INSERT TO authenticated WITH CHECK (
    user_id = auth.uid()::text
    AND (
      NOT is_shared
      OR (career_id IS NOT NULL AND public.is_docente(career_id))
    )
  );

CREATE POLICY "study_files_update" ON public.study_files
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid()::text)
  WITH CHECK (
    user_id = auth.uid()::text
    AND (
      NOT is_shared
      OR (career_id IS NOT NULL AND public.is_docente(career_id))
    )
  );

CREATE POLICY "study_files_delete" ON public.study_files
  FOR DELETE TO authenticated USING (user_id = auth.uid()::text);

CREATE INDEX IF NOT EXISTS idx_study_files_shared
  ON public.study_files(career_id, subject) WHERE is_shared;

COMMIT;
