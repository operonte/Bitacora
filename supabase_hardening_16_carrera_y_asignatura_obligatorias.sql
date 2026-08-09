-- Bitácora — endurecimiento 16: carrera y asignatura obligatorias y coherentes
--
-- Esto es una app de carreras universitarias. Un archivo, una reunión o una
-- tarea sin carrera y sin asignatura no significan nada, y una asignatura de
-- Informática colgando de Teología es directamente información falsa.
--
-- Hasta ahora eso solo lo impedían los formularios. La base aceptaba cualquier
-- combinación, así que bastaba una versión vieja de la app, una escritura
-- offline que se subiera después, o el escaneo de Drive, para meter filas
-- incoherentes — y de hecho las hubo, y hubo que corregirlas a mano.
--
-- Qué se acepta como asignatura de una carrera:
--
--   1. Una de las `predefined_subjects` de esa carrera.
--   2. Una materia propia del usuario (tabla `subjects`), que no está atada a
--      ninguna carrera por diseño.
--
-- Cuándo se comprueba: siempre al INSERT, y al UPDATE solo si cambió la
-- carrera o la asignatura. Sin esa condición, renombrar una materia en el
-- panel dejaría atrapadas las filas viejas: cualquier edición posterior
-- —aunque fuera solo el nombre del archivo— sería rechazada y no habría forma
-- de arreglarlas desde la app.

BEGIN;

CREATE OR REPLACE FUNCTION public.assert_subject_belongs_to_career()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_career_name TEXT;
  v_ok          BOOLEAN;
BEGIN
  IF NEW.career_id IS NULL OR btrim(NEW.career_id) = '' THEN
    RAISE EXCEPTION 'Falta la carrera: no se puede guardar sin ella';
  END IF;

  IF NEW.subject IS NULL OR btrim(NEW.subject) = '' THEN
    RAISE EXCEPTION 'Falta la asignatura: no se puede guardar sin ella';
  END IF;

  SELECT c.name INTO v_career_name FROM public.careers c WHERE c.id = NEW.career_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La carrera % no existe', NEW.career_id;
  END IF;

  SELECT EXISTS (
    -- Materia de la carrera.
    SELECT 1
      FROM public.careers c,
           LATERAL jsonb_array_elements(c.predefined_subjects) AS s
     WHERE c.id = NEW.career_id
       AND lower(btrim(s->>'name')) = lower(btrim(NEW.subject))
    UNION ALL
    -- Materia propia de quien escribe.
    SELECT 1
      FROM public.subjects sub
     WHERE sub.user_id = auth.uid()
       AND lower(btrim(sub.name)) = lower(btrim(NEW.subject))
  ) INTO v_ok;

  IF NOT v_ok THEN
    RAISE EXCEPTION
      'La asignatura "%" no pertenece a la carrera "%"',
      NEW.subject, v_career_name;
  END IF;

  RETURN NEW;
END;
$$;

-- Solo cuando cambia lo que se valida. Ver la nota de arriba sobre renombrar
-- materias.
CREATE OR REPLACE FUNCTION public.subject_or_career_changed()
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
AS $$ SELECT TRUE $$;

DROP TRIGGER IF EXISTS study_files_subject_matches_career ON public.study_files;
CREATE TRIGGER study_files_subject_matches_career
  BEFORE INSERT ON public.study_files
  FOR EACH ROW EXECUTE FUNCTION public.assert_subject_belongs_to_career();

DROP TRIGGER IF EXISTS study_files_subject_matches_career_upd ON public.study_files;
CREATE TRIGGER study_files_subject_matches_career_upd
  BEFORE UPDATE ON public.study_files
  FOR EACH ROW
  WHEN (OLD.subject IS DISTINCT FROM NEW.subject
     OR OLD.career_id IS DISTINCT FROM NEW.career_id)
  EXECUTE FUNCTION public.assert_subject_belongs_to_career();

DROP TRIGGER IF EXISTS meetings_subject_matches_career ON public.meetings;
CREATE TRIGGER meetings_subject_matches_career
  BEFORE INSERT ON public.meetings
  FOR EACH ROW EXECUTE FUNCTION public.assert_subject_belongs_to_career();

DROP TRIGGER IF EXISTS meetings_subject_matches_career_upd ON public.meetings;
CREATE TRIGGER meetings_subject_matches_career_upd
  BEFORE UPDATE ON public.meetings
  FOR EACH ROW
  WHEN (OLD.subject IS DISTINCT FROM NEW.subject
     OR OLD.career_id IS DISTINCT FROM NEW.career_id)
  EXECUTE FUNCTION public.assert_subject_belongs_to_career();

DROP TRIGGER IF EXISTS shared_tasks_subject_matches_career ON public.shared_tasks;
CREATE TRIGGER shared_tasks_subject_matches_career
  BEFORE INSERT ON public.shared_tasks
  FOR EACH ROW EXECUTE FUNCTION public.assert_subject_belongs_to_career();

DROP TRIGGER IF EXISTS shared_tasks_subject_matches_career_upd ON public.shared_tasks;
CREATE TRIGGER shared_tasks_subject_matches_career_upd
  BEFORE UPDATE ON public.shared_tasks
  FOR EACH ROW
  WHEN (OLD.subject IS DISTINCT FROM NEW.subject
     OR OLD.career_id IS DISTINCT FROM NEW.career_id)
  EXECUTE FUNCTION public.assert_subject_belongs_to_career();

DROP TRIGGER IF EXISTS tasks_subject_matches_career ON public.tasks;
CREATE TRIGGER tasks_subject_matches_career
  BEFORE INSERT ON public.tasks
  FOR EACH ROW EXECUTE FUNCTION public.assert_subject_belongs_to_career();

DROP TRIGGER IF EXISTS tasks_subject_matches_career_upd ON public.tasks;
CREATE TRIGGER tasks_subject_matches_career_upd
  BEFORE UPDATE ON public.tasks
  FOR EACH ROW
  WHEN (OLD.subject IS DISTINCT FROM NEW.subject
     OR OLD.career_id IS DISTINCT FROM NEW.career_id)
  EXECUTE FUNCTION public.assert_subject_belongs_to_career();

DROP FUNCTION IF EXISTS public.subject_or_career_changed();

COMMIT;

-- Verificación: esto debe fallar con "no pertenece a la carrera".
--
-- INSERT INTO public.study_files (id, name, subject, drive_link, user_id, career_id)
-- VALUES ('prueba', 'x', 'Álgebra', 'https://x', auth.uid(), 'teologia');
