-- Bitácora — arregla otro bug real: el docente aparecía en la lista de
-- asistencia de su propia clase y en el panel de riesgo de su propia
-- carrera, como si fuera un alumno más a marcar o a poner en alerta.
--
-- get_attendance_roster y get_student_risk hacían FROM user_careers uc
-- WHERE uc.career_id = p_career_id sin filtrar el rol — a diferencia de
-- get_career_members o admin_list_career_members, donde mezclar roles es
-- intencional (son directorios de "quién hay"), acá el propósito es
-- "a quién le tomo asistencia" / "quién de mis alumnos está en riesgo", y
-- el propio docente (o un co-docente) nunca debería aparecer ahí.
--
-- user_careers_role_chk solo permite 'estudiante' o 'docente', así que el
-- filtro es exacto.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_attendance_roster(
  p_career_id  TEXT,
  p_subject    TEXT,
  p_class_date DATE
)
RETURNS TABLE (
  user_id      UUID,
  display_name TEXT,
  email        TEXT,
  status       TEXT
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
    SELECT p.id, p.display_name, p.email,
           COALESCE(a.status, 'sin_marcar')
      FROM public.user_careers uc
      JOIN public.profiles p ON p.id = uc.user_id
      LEFT JOIN public.attendance a
             ON a.career_id = p_career_id AND a.subject = p_subject
            AND a.class_date = p_class_date AND a.user_id = uc.user_id
     WHERE uc.career_id = p_career_id
       AND uc.role = 'estudiante'
     ORDER BY p.display_name NULLS LAST;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_student_risk(p_career_id TEXT)
RETURNS TABLE (
  user_id           UUID,
  display_name      TEXT,
  email             TEXT,
  missed_tasks      BIGINT,
  attendance_rate   NUMERIC,
  attendance_marked BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now_ms BIGINT := (extract(epoch from now()) * 1000)::bigint;
BEGIN
  IF NOT public.is_docente(p_career_id) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  RETURN QUERY
    SELECT
      uc.user_id,
      p.display_name,
      p.email,
      COALESCE(missed.cnt, 0) AS missed_tasks,
      CASE WHEN COALESCE(att.total, 0) = 0 THEN NULL
           ELSE ROUND(100.0 * COALESCE(att.presentes, 0) / att.total, 0)
      END AS attendance_rate,
      COALESCE(att.total, 0) AS attendance_marked
    FROM public.user_careers uc
    JOIN public.profiles p ON p.id = uc.user_id
    LEFT JOIN LATERAL (
      SELECT count(*) AS cnt
        FROM public.shared_tasks st
        LEFT JOIN public.task_progress tp
               ON tp.task_id = st.id AND tp.user_id = uc.user_id
       WHERE st.career_id = p_career_id
         AND st.is_official
         AND st.due_date < v_now_ms
         AND NOT (COALESCE(tp.is_completed, FALSE) AND COALESCE(tp.is_submitted, FALSE))
    ) missed ON TRUE
    LEFT JOIN LATERAL (
      SELECT count(*) AS total,
             count(*) FILTER (WHERE status IN ('presente', 'tarde')) AS presentes
        FROM public.attendance a
       WHERE a.career_id = p_career_id AND a.user_id = uc.user_id
    ) att ON TRUE
   WHERE uc.career_id = p_career_id
     AND uc.role = 'estudiante'
   ORDER BY missed_tasks DESC, attendance_rate ASC NULLS LAST;
END;
$$;

COMMIT;
