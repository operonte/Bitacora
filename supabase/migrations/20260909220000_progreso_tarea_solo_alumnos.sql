-- Bitácora — "Ver progreso del grupo" (ahora la vista principal de una
-- tarea oficial para el docente que la creó, ver el fix de la app del mismo
-- día) listaba a TODOS los miembros de la carrera como si le debieran la
-- tarea: otros docentes de otras asignaturas incluidos. Mismo bug, mismo
-- motivo, que fix_docente_en_su_propio_roster ya corrigió para asistencia y
-- panel de riesgo — acá faltaba aplicarlo.
--
-- Se acota igual que get_attendance_roster: solo role = 'estudiante', y si
-- la asignatura de la tarea tiene semestre cargado en el catálogo, solo los
-- alumnos de ese semestre (subject_semester ya existe para esto). Sin
-- semestre cargado, se degrada a toda la carrera — el comportamiento de hoy
-- para esa asignatura, no uno peor.

BEGIN;

-- Cambia el tipo de fila (columnas nuevas/reordenadas respecto a lo que hay
-- en el servidor); un CREATE OR REPLACE no puede cambiar eso, hay que
-- borrarla antes — mismo caso que admin_list_career_members/get_student_tasks.
DROP FUNCTION IF EXISTS public.get_task_submission_status(UUID);

CREATE FUNCTION public.get_task_submission_status(p_task_id UUID)
RETURNS TABLE (
  user_id      UUID,
  display_name TEXT,
  email        TEXT,
  is_completed BOOLEAN,
  is_submitted BOOLEAN,
  updated_at   BIGINT
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
  -- Solo quien creó la tarea puede ver el progreso de los demás. Sin esto,
  -- cualquier miembro de la carrera podría espiar el avance de sus
  -- compañeros en una tarea ajena.
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
      COALESCE(tp.updated_at, 0)
    FROM public.user_careers uc
    JOIN public.profiles p ON p.id = uc.user_id
    LEFT JOIN public.task_progress tp
           ON tp.task_id = p_task_id AND tp.user_id = uc.user_id
   WHERE uc.career_id = v_career_id
     AND uc.role = 'estudiante'
     AND (v_semester IS NULL OR uc.semester = v_semester)
   ORDER BY p.display_name NULLS LAST;
END;
$$;

-- DROP FUNCTION se llevó puestos los GRANT que tenía (nunca los tuvo
-- explícitos; corría con el default de PUBLIC). Se deja explícito y acotado
-- a authenticated, mismo patrón que el resto de los RPC nuevos.
REVOKE ALL ON FUNCTION public.get_task_submission_status(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_task_submission_status(UUID) TO authenticated;

COMMIT;
