-- Bitácora — la bandeja de progreso por tarea también informa el archivo
-- que cada alumno adjuntó.
--
-- get_task_submission_status ya le mostraba al docente, tarea por tarea,
-- quién entregó y con qué nota/comentario — pero no el archivo en sí: para
-- abrirlo había que ir a la Ficha del alumno, uno por uno. Mismo LEFT JOIN
-- contra study_files que ya usa get_student_tasks (entrega_visible_docente),
-- así que la RLS que habilita verlo ya existe — esto solo agrega la columna.

BEGIN;

DROP FUNCTION IF EXISTS public.get_task_submission_status(UUID);

CREATE FUNCTION public.get_task_submission_status(p_task_id UUID)
RETURNS TABLE (
  user_id                 UUID,
  display_name            TEXT,
  email                   TEXT,
  is_completed            BOOLEAN,
  is_submitted            BOOLEAN,
  updated_at              BIGINT,
  teacher_comment         TEXT,
  teacher_comment_at      BIGINT,
  grade                   TEXT,
  attached_file_name      TEXT,
  attached_file_link      TEXT,
  attached_file_drive_id  TEXT,
  attached_file_mime      TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_career_id TEXT;
BEGIN
  SELECT career_id INTO v_career_id
    FROM public.shared_tasks
   WHERE id = p_task_id AND created_by = auth.uid();

  IF v_career_id IS NULL THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  RETURN QUERY
    SELECT
      p.id,
      p.display_name,
      p.email,
      COALESCE(tp.is_completed, FALSE),
      COALESCE(tp.is_submitted, FALSE),
      COALESCE(tp.updated_at, 0),
      tp.teacher_comment,
      tp.teacher_comment_at,
      tp.grade,
      sf.name,
      sf.drive_link,
      sf.drive_file_id,
      sf.mime_type
    FROM public.user_careers uc
    JOIN public.profiles p ON p.id = uc.user_id
    LEFT JOIN public.task_progress tp
           ON tp.task_id = p_task_id AND tp.user_id = uc.user_id
    LEFT JOIN public.study_files sf
           ON sf.task_id = p_task_id::text AND sf.user_id = uc.user_id::text
   WHERE uc.career_id = v_career_id
   ORDER BY p.display_name NULLS LAST;
END;
$$;

REVOKE ALL ON FUNCTION public.get_task_submission_status(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_task_submission_status(UUID) TO authenticated;

COMMIT;
