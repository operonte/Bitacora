-- Bitácora — endurecimiento menor, mismo patrón que el resto de la sesión:
-- get_student_tasks/get_student_attendance ("Ficha del alumno") exigen ser
-- docente de la carrera, pero no comprueban que p_student_id sea realmente
-- un alumno — nada en la UI llama a esto con otro UUID (el selector sale de
-- get_student_risk, que ya filtra por rol), pero el RPC en sí, llamado
-- directo, dejaba pedir la ficha de un colega docente. Se agrega el mismo
-- chequeo de rol que ya tienen get_attendance_roster/get_task_submission_
-- status/get_career_grades.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_student_tasks(
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

  IF NOT EXISTS (
    SELECT 1 FROM public.user_careers uc
     WHERE uc.user_id = p_student_id
       AND uc.career_id = p_career_id
       AND uc.role = 'estudiante'
  ) THEN
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

CREATE OR REPLACE FUNCTION public.get_student_attendance(
  p_career_id TEXT,
  p_student_id UUID
)
RETURNS TABLE (
  subject    TEXT,
  class_date DATE,
  status     TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_docente(p_career_id) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.user_careers uc
     WHERE uc.user_id = p_student_id
       AND uc.career_id = p_career_id
       AND uc.role = 'estudiante'
  ) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  RETURN QUERY
    SELECT a.subject, a.class_date, a.status
      FROM public.attendance a
     WHERE a.career_id = p_career_id AND a.user_id = p_student_id
     ORDER BY a.class_date DESC;
END;
$$;

COMMIT;
