-- Bitácora — Fase 2 del ecosistema docente: comentario del docente por
-- alumno en una tarea compartida.
--
-- task_progress ya guarda el estado (realizada/enviada) de cada alumno; le
-- falta un lugar para que quien creó la tarea deje una nota puntual ("falta
-- la bibliografía", "bien, pero revisa el punto 3") sin mandarla por otro
-- canal. Mismo patrón que get_task_submission_status: RPC SECURITY DEFINER
-- que exige ser el creador, sin política RLS nueva sobre task_progress.

BEGIN;

ALTER TABLE public.task_progress
  ADD COLUMN IF NOT EXISTS teacher_comment TEXT,
  ADD COLUMN IF NOT EXISTS teacher_comment_at BIGINT;

CREATE OR REPLACE FUNCTION public.set_task_teacher_comment(
  p_task_id UUID,
  p_user_id UUID,
  p_comment TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.shared_tasks
     WHERE id = p_task_id AND created_by = auth.uid()
  ) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  INSERT INTO public.task_progress (user_id, task_id, teacher_comment, teacher_comment_at)
  VALUES (p_user_id, p_task_id, NULLIF(trim(p_comment), ''), (extract(epoch from now()) * 1000)::bigint)
  ON CONFLICT (user_id, task_id) DO UPDATE
    SET teacher_comment = EXCLUDED.teacher_comment,
        teacher_comment_at = EXCLUDED.teacher_comment_at;
END;
$$;

-- get_task_submission_status también informa el comentario, para que el
-- panel de progreso lo muestre sin una segunda consulta. Cambia el tipo de
-- fila, así que hay que borrarla antes de recrearla.
DROP FUNCTION IF EXISTS public.get_task_submission_status(UUID);

CREATE FUNCTION public.get_task_submission_status(p_task_id UUID)
RETURNS TABLE (
  user_id             UUID,
  display_name        TEXT,
  email               TEXT,
  is_completed        BOOLEAN,
  is_submitted        BOOLEAN,
  updated_at          BIGINT,
  teacher_comment     TEXT,
  teacher_comment_at  BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_career_id TEXT;
BEGIN
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
      COALESCE(tp.updated_at, 0),
      tp.teacher_comment,
      tp.teacher_comment_at
    FROM public.user_careers uc
    JOIN public.profiles p ON p.id = uc.user_id
    LEFT JOIN public.task_progress tp
           ON tp.task_id = p_task_id AND tp.user_id = uc.user_id
   WHERE uc.career_id = v_career_id
   ORDER BY p.display_name NULLS LAST;
END;
$$;

REVOKE ALL ON FUNCTION public.set_task_teacher_comment(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_task_teacher_comment(UUID, UUID, TEXT) TO authenticated;

COMMIT;
