-- A veces el docente no crea la tarea oficial él mismo; si un alumno la
-- sube como tarea compartida de esa asignatura, debería poder evaluarla
-- igual que si fuera oficial — "las mismas reglas". Antes get_task_
-- submission_status exigía ser quien la creó; ahora también vale ser
-- docente de esa asignatura en esa carrera (teacher_subjects), sin importar
-- quién la haya creado — mismo criterio que ya usa can_see_meeting_subject.
CREATE OR REPLACE FUNCTION public.get_task_submission_status(p_task_id uuid)
 RETURNS TABLE(user_id uuid, display_name text, email text, is_completed boolean, is_submitted boolean, updated_at bigint, teacher_comment text, teacher_comment_at bigint, grade text, attached_file_name text, attached_file_link text, attached_file_drive_id text, attached_file_mime text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_career_id TEXT;
  v_subject   TEXT;
  v_semester  TEXT;
BEGIN
  SELECT st.career_id, st.subject INTO v_career_id, v_subject
    FROM public.shared_tasks st
   WHERE st.id = p_task_id
     AND (
       st.created_by = auth.uid()
       OR (
         public.is_docente(st.career_id)
         AND EXISTS (
               SELECT 1 FROM public.teacher_subjects ts
                WHERE ts.user_id = auth.uid()
                  AND ts.career_id = st.career_id
                  AND ts.subject = st.subject
             )
       )
     );

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
$function$;
