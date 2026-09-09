-- Bitácora — bug real: al nombrar docente a una cuenta no se le pide de qué
-- asignatura(s), así que meetings_select lo trataba como a cualquier otro
-- miembro y le mostraba el calendario COMPLETO de la carrera, aunque un
-- docente nunca imparte la carrera entera, solo ciertas asignaturas.
--
-- teacher_subjects ya existe (semestre_y_asignaturas_docente) y ya tiene su
-- propia pantalla de autoservicio (Configuración → Mis asignaturas) — solo
-- faltaba que meetings_select la consultara. Para alumnos no cambia nada:
-- siguen viendo toda la carrera, como hoy (eso no se reportó como bug).
--
-- No se reutiliza can_see_shared_subject_content (semestre) porque esa es la
-- lógica del lado ALUMNO; acá el cruce es distinto: el docente no tiene
-- semestre, tiene una lista de asignaturas que él mismo declaró.

BEGIN;

CREATE OR REPLACE FUNCTION public.can_see_meeting_subject(p_career_id TEXT, p_subject TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT NOT public.is_docente(p_career_id)
      OR EXISTS (
        SELECT 1 FROM public.teacher_subjects ts
         WHERE ts.user_id = auth.uid()
           AND ts.career_id = p_career_id
           AND ts.subject = p_subject
      );
$$;

REVOKE ALL ON FUNCTION public.can_see_meeting_subject(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_see_meeting_subject(TEXT, TEXT) TO authenticated;

DROP POLICY IF EXISTS "meetings_select" ON public.meetings;
CREATE POLICY "meetings_select" ON public.meetings
  FOR SELECT USING (
    auth.uid() = user_id
    OR (
      is_private = false
      AND EXISTS (
        SELECT 1 FROM public.user_careers uc
         WHERE uc.user_id = auth.uid() AND uc.career_id = meetings.career_id
      )
      AND public.can_see_meeting_subject(meetings.career_id, meetings.subject)
    )
  );

COMMIT;
