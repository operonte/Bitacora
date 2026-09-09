-- Bitácora — ficha del alumno para el docente.
--
-- El panel de riesgo ya resumía cuántas tareas atrasadas y qué % de
-- asistencia tiene cada alumno; esto agrega el detalle: qué tarea puntual
-- está atrasada, qué nota tiene cada una, y el historial de asistencia día
-- por día. Dos RPC nuevos, mismo patrón que el resto del ecosistema docente
-- (SECURITY DEFINER, exige is_docente() de la carrera).

BEGIN;

-- Todas las tareas compartidas de la carrera con el progreso de UN alumno
-- puntual — antes solo existía get_task_submission_status, que es al revés
-- (una tarea, todos los alumnos).
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
  teacher_comment     TEXT
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
      tp.teacher_comment
    FROM public.shared_tasks st
    LEFT JOIN public.task_progress tp
           ON tp.task_id = st.id AND tp.user_id = p_student_id
   WHERE st.career_id = p_career_id
   ORDER BY st.due_date DESC;
END;
$$;

-- Asistencia de UN alumno puntual, para el docente — get_my_attendance ya
-- hacía esto pero solo para el propio usuario (auth.uid()), sin chequeo de
-- rol porque no hacía falta. Acá el chequeo es obligatorio: sin él,
-- cualquiera podría pedir la asistencia de cualquiera.
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

  RETURN QUERY
    SELECT a.subject, a.class_date, a.status
      FROM public.attendance a
     WHERE a.career_id = p_career_id AND a.user_id = p_student_id
     ORDER BY a.class_date DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.get_student_tasks(TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_student_attendance(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_student_tasks(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_student_attendance(TEXT, UUID) TO authenticated;

COMMIT;
