-- Bitácora — nota simple por tarea y alumno.
--
-- No es un libro de calificaciones: es un campo de texto libre ("6.5",
-- "Aprobado", "18/20") en task_progress, igual patrón que teacher_comment.
-- Sin escala fija a propósito — cada docente califica como quiera, Bitácora
-- solo guarda y muestra el valor.

BEGIN;

ALTER TABLE public.task_progress
  ADD COLUMN IF NOT EXISTS grade TEXT;

CREATE OR REPLACE FUNCTION public.set_task_grade(
  p_task_id UUID,
  p_user_id UUID,
  p_grade   TEXT
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

  INSERT INTO public.task_progress (user_id, task_id, grade)
  VALUES (p_user_id, p_task_id, NULLIF(trim(p_grade), ''))
  ON CONFLICT (user_id, task_id) DO UPDATE
    SET grade = EXCLUDED.grade;
END;
$$;

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
  teacher_comment_at  BIGINT,
  grade               TEXT
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
      tp.teacher_comment_at,
      tp.grade
    FROM public.user_careers uc
    JOIN public.profiles p ON p.id = uc.user_id
    LEFT JOIN public.task_progress tp
           ON tp.task_id = p_task_id AND tp.user_id = uc.user_id
   WHERE uc.career_id = v_career_id
   ORDER BY p.display_name NULLS LAST;
END;
$$;

REVOKE ALL ON FUNCTION public.set_task_grade(UUID, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_task_grade(UUID, UUID, TEXT) TO authenticated;

COMMIT;
