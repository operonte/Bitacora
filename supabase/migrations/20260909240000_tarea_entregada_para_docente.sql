-- Bitácora — bug real: una tarea oficial/compartida que un docente asigna a
-- su carrera nunca aparecía en "Tareas entregadas", porque pending/overdue/
-- delivered en el cliente miran task_progress DEL PROPIO USUARIO
-- (isCompleted/isSubmitted) — y el docente no "hace" la tarea que él mismo
-- asignó, así que esos dos campos se quedan en false para siempre.
--
-- Se agrega un RPC que calcula, por cada tarea compartida creada por
-- auth.uid() en una carrera donde es docente, si ya nadie se la debe — mismo
-- roster (alumnos, acotados por semestre si la asignatura lo tiene cargado)
-- que ya usa get_task_submission_status. AppState.pendingTasks/overdueTasks/
-- deliveredTasks lo usa en vez de isCompleted/isSubmitted solo para esas
-- tareas puntuales (ver el fix del cliente del mismo día).
--
-- Sin alumnos que la deban todavía (nadie inscrito, o nadie del semestre
-- correcto), se considera NO entregada — no tiene sentido mostrarla como
-- lista si no hay a quién.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_my_created_shared_tasks_status()
RETURNS TABLE (
  task_id       UUID,
  all_delivered BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
BEGIN
  RETURN QUERY
    SELECT
      st.id,
      EXISTS (
        SELECT 1 FROM public.user_careers uc
         WHERE uc.career_id = st.career_id
           AND uc.role = 'estudiante'
           AND (
             public.subject_semester(st.career_id, st.subject) IS NULL
             OR uc.semester = public.subject_semester(st.career_id, st.subject)
           )
      )
      AND NOT EXISTS (
        SELECT 1
          FROM public.user_careers uc
          LEFT JOIN public.task_progress tp
                 ON tp.task_id = st.id AND tp.user_id = uc.user_id
         WHERE uc.career_id = st.career_id
           AND uc.role = 'estudiante'
           AND (
             public.subject_semester(st.career_id, st.subject) IS NULL
             OR uc.semester = public.subject_semester(st.career_id, st.subject)
           )
           AND NOT (
             COALESCE(tp.is_completed, FALSE) AND COALESCE(tp.is_submitted, FALSE)
           )
      )
    FROM public.shared_tasks st
   WHERE st.created_by = auth.uid()
     AND public.is_docente(st.career_id);
END;
$$;

REVOKE ALL ON FUNCTION public.get_my_created_shared_tasks_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_created_shared_tasks_status() TO authenticated;

COMMIT;
