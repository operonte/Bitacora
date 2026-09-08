-- Bitácora — primer paso del ecosistema docente: saber quién entregó.
--
-- Quien crea una tarea compartida hoy no tiene forma de ver el progreso de
-- sus compañeros de carrera: task_progress solo se lee a uno mismo
-- (política "task_progress_own"). Es el hueco más pedido por cualquiera que
-- asigna trabajo a un grupo — Classroom, Moodle y cualquier LMS lo resuelven
-- de entrada.
--
-- Se resuelve con un RPC SECURITY DEFINER, igual que admin_list_career_members
-- en supabase_hardening_14: no se abre ninguna política nueva sobre
-- task_progress. Si mañana alguien llama al API directo sin pasar por este
-- RPC, sigue sin poder leer el progreso ajeno. La autorización vive adentro
-- de la función, no en un permiso amplio.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_task_submission_status(p_task_id UUID)
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
BEGIN
  -- Solo quien creó la tarea puede ver el progreso de los demás. Sin esto,
  -- cualquier miembro de la carrera (shared_tasks_member permite leer/escribir
  -- a todos) podría espiar el avance de sus compañeros en una tarea ajena.
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
      COALESCE(tp.updated_at, 0)
    FROM public.user_careers uc
    JOIN public.profiles p ON p.id = uc.user_id
    LEFT JOIN public.task_progress tp
           ON tp.task_id = p_task_id AND tp.user_id = uc.user_id
   WHERE uc.career_id = v_career_id
   ORDER BY p.display_name NULLS LAST;
END;
$$;

REVOKE ALL ON FUNCTION public.get_task_submission_status(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_task_submission_status(UUID) TO authenticated;

COMMIT;
