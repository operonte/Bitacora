-- Bitácora — regresión propia: al arreglar get_task_submission_status para
-- excluir a otros docentes y acotar por semestre (progreso_tarea_solo_
-- alumnos, mismo día), la reescribí a partir de una definición vieja
-- (estado_entrega_tarea) sin saber que archivo_en_progreso_tarea ya la
-- había ampliado con nota, comentario y archivo adjunto. El servidor se
-- quedó con la versión sin esas columnas — "Ver progreso del grupo" dejó de
-- mostrar nota/comentario/archivo para cualquier alumno ya sincronizado,
-- aunque el cliente (task_details_dialog.dart) los sigue pidiendo.
--
-- Se restauran las columnas de archivo_en_progreso_tarea y se conserva el
-- filtro de rol/semestre de progreso_tarea_solo_alumnos — las dos cosas a
-- la vez, no una a costa de la otra.

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
  v_subject   TEXT;
  v_semester  TEXT;
BEGIN
  -- Solo quien creó la tarea puede ver el progreso de los demás.
  SELECT career_id, subject INTO v_career_id, v_subject
    FROM public.shared_tasks
   WHERE id = p_task_id AND created_by = auth.uid();

  IF v_career_id IS NULL THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  v_semester := public.subject_semester(v_career_id, v_subject);

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
     AND uc.role = 'estudiante'
     AND (v_semester IS NULL OR uc.semester = v_semester)
   ORDER BY p.display_name NULLS LAST;
END;
$$;

REVOKE ALL ON FUNCTION public.get_task_submission_status(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_task_submission_status(UUID) TO authenticated;

COMMIT;
