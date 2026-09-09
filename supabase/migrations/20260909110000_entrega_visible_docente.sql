-- Bitácora — el docente ve el archivo que el alumno adjuntó a su tarea oficial.
--
-- Mismo mecanismo que material_docente_compartido, en espejo: en vez de
-- "compartido con toda la carrera", acá es "visible para quien creó la
-- tarea oficial a la que se adjuntó". RLS real, no un RPC que hace de
-- excepción — así el docente puede seguir usando SELECT normal sobre
-- study_files (por ejemplo desde get_student_tasks) sin depender de un
-- bypass en cada función nueva que se agregue después.

BEGIN;

DROP POLICY IF EXISTS "study_files_select" ON public.study_files;

CREATE POLICY "study_files_select" ON public.study_files
  FOR SELECT TO authenticated USING (
    user_id = auth.uid()::text
    OR (
      is_shared
      AND category = 'guia'
      AND career_id IS NOT NULL
      AND public.can_see_shared_subject_content(career_id, subject)
    )
    OR (
      task_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM public.shared_tasks st
         WHERE st.id::text = task_id
           AND st.is_official
           AND st.created_by = auth.uid()
      )
    )
  );

-- get_student_tasks ahora también informa el archivo que el alumno adjuntó
-- a cada tarea, si hay uno. Cambia la forma del resultado (columnas nuevas),
-- así que hay que borrarla antes: un CREATE OR REPLACE no puede cambiar el
-- tipo de retorno.
DROP FUNCTION IF EXISTS public.get_student_tasks(TEXT, UUID);

CREATE FUNCTION public.get_student_tasks(
  p_career_id TEXT,
  p_student_id UUID
)
RETURNS TABLE (
  task_id             UUID,
  title               TEXT,
  subject             TEXT,
  due_date            BIGINT,
  is_official         BOOLEAN,
  is_completed        BOOLEAN,
  is_submitted        BOOLEAN,
  progress_updated_at BIGINT,
  grade               TEXT,
  teacher_comment     TEXT,
  attached_file_name     TEXT,
  attached_file_link     TEXT,
  attached_file_drive_id TEXT,
  attached_file_mime     TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_docente(p_career_id) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  RETURN QUERY
    SELECT
      st.id,
      st.title,
      st.subject,
      st.due_date,
      st.is_official,
      COALESCE(tp.is_completed, FALSE),
      COALESCE(tp.is_submitted, FALSE),
      COALESCE(tp.updated_at, 0),
      tp.grade,
      tp.teacher_comment,
      sf.name,
      sf.drive_link,
      sf.drive_file_id,
      sf.mime_type
    FROM public.shared_tasks st
    LEFT JOIN public.task_progress tp
           ON tp.task_id = st.id AND tp.user_id = p_student_id
    LEFT JOIN public.study_files sf
           ON sf.task_id = st.id::text AND sf.user_id = p_student_id::text
   WHERE st.career_id = p_career_id
   ORDER BY st.due_date DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_student_tasks(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_student_tasks(TEXT, UUID) TO authenticated;

COMMIT;
