-- Bitácora — Fase 5 del ecosistema docente: notas y asistencia de TODA la
-- carrera, no solo de la asignatura que el docente imparte.
--
-- A diferencia de reuniones (que sí se acotan por teacher_subjects, ver
-- 20260909210000), acá el pedido explícito fue lo contrario: un docente
-- puede dar feedback cruzado con sus colegas, así que necesita ver notas y
-- asistencia de TODAS las asignaturas de su carrera, no solo la suya. Mismo
-- patrón que get_student_risk: RPC SECURITY DEFINER, exige is_docente(),
-- sin política RLS nueva sobre task_progress/attendance.
--
-- Ambas tablas son "una fila por cosa" (una nota por tarea, una asistencia
-- por asignatura), no una grilla con celdas fusionadas: un alumno con tres
-- tareas calificadas en la misma materia da tres filas, no una sola con las
-- tres notas apiladas — así lo pidió el que la va a usar.

BEGIN;

-- Una fila por nota (task_progress.grade no vacío) de un alumno real de la
-- carrera — se excluye a otros docentes con el mismo filtro por rol que ya
-- se usa en get_attendance_roster/get_task_submission_status.
CREATE OR REPLACE FUNCTION public.get_career_grades(p_career_id TEXT)
RETURNS TABLE (
  student_id      UUID,
  student_name    TEXT,
  student_email   TEXT,
  subject         TEXT,
  task_title      TEXT,
  grade           TEXT,
  updated_at      BIGINT
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
      p.id,
      p.display_name,
      p.email,
      st.subject,
      st.title,
      tp.grade,
      tp.updated_at
    FROM public.task_progress tp
    JOIN public.shared_tasks st ON st.id = tp.task_id
    JOIN public.profiles p ON p.id = tp.user_id
    JOIN public.user_careers uc
      ON uc.user_id = tp.user_id AND uc.career_id = p_career_id
    WHERE st.career_id = p_career_id
      AND uc.role = 'estudiante'
      AND tp.grade IS NOT NULL AND tp.grade <> ''
    ORDER BY p.display_name NULLS LAST, st.subject, tp.updated_at DESC;
END;
$$;

-- Una fila por (alumno, asignatura) con su % de asistencia en esa materia —
-- a diferencia de get_student_risk, que da un único % mezclando toda la
-- carrera.
CREATE OR REPLACE FUNCTION public.get_career_attendance_summary(p_career_id TEXT)
RETURNS TABLE (
  student_id      UUID,
  student_name    TEXT,
  student_email   TEXT,
  subject         TEXT,
  attendance_rate NUMERIC,
  marked          BIGINT
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
      p.id,
      p.display_name,
      p.email,
      a.subject,
      ROUND(
        100.0 * count(*) FILTER (WHERE a.status IN ('presente', 'tarde'))
        / count(*),
        0
      ) AS attendance_rate,
      count(*) AS marked
    FROM public.attendance a
    JOIN public.profiles p ON p.id = a.user_id
    JOIN public.user_careers uc
      ON uc.user_id = a.user_id AND uc.career_id = p_career_id
    WHERE a.career_id = p_career_id
      AND uc.role = 'estudiante'
    GROUP BY p.id, p.display_name, p.email, a.subject
    ORDER BY p.display_name NULLS LAST, a.subject;
END;
$$;

REVOKE ALL ON FUNCTION public.get_career_grades(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_career_attendance_summary(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_career_grades(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_career_attendance_summary(TEXT) TO authenticated;

COMMIT;
