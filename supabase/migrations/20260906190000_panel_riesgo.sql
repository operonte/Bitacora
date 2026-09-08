-- Bitácora — panel de riesgo del docente.
--
-- No es analítica avanzada ni IA: una regla simple sobre datos que la app ya
-- junta (tareas oficiales sin entregar, asistencia marcada), que es
-- justamente lo que la investigación dice que funciona en instituciones
-- chicas sin infraestructura de datos. RPC SECURITY DEFINER de solo lectura,
-- reutiliza is_docente() de la migración de asistencia.

BEGIN;

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
      -- Tareas oficiales ya vencidas que este alumno no dejó
      -- completada+enviada. due_date es BIGINT (epoch ms), como en el resto
      -- del modelo de tareas.
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
   ORDER BY missed_tasks DESC, attendance_rate ASC NULLS LAST;
END;
$$;

REVOKE ALL ON FUNCTION public.get_student_risk(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_student_risk(TEXT) TO authenticated;

COMMIT;
