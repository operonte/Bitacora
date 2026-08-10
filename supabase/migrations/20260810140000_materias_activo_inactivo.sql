-- Bitácora — materias predefinidas: activa/inactiva por semestre
--
-- Mismo problema que las carreras (migración 20260810110000), un nivel más
-- abajo: una materia de un semestre anterior no debería poder recibir tareas
-- ni reuniones nuevas, pero los archivos que ya tiene (y los que se quieran
-- seguir organizando ahí, en Archivos/Material docente) tienen que seguir
-- funcionando igual.
--
-- No hace falta una columna nueva: Subject ya vive como JSON dentro de
-- careers.predefined_subjects, y el modelo Dart (subject_model.dart) ya
-- manda 'isActive' en cada materia desde este cambio. Acá solo se agrega la
-- verificación del lado del servidor — el cliente ya filtra en los
-- selectores de tarea/reunión, esto es que no se pueda saltar.

CREATE OR REPLACE FUNCTION public.assert_subject_belongs_to_career()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_career_name    TEXT;
  v_career_active  BOOLEAN;
  v_ok             BOOLEAN;
  v_subject_active BOOLEAN;
BEGIN
  IF NEW.career_id IS NULL OR btrim(NEW.career_id) = '' THEN
    RAISE EXCEPTION 'Falta la carrera: no se puede guardar sin ella';
  END IF;

  IF NEW.subject IS NULL OR btrim(NEW.subject) = '' THEN
    RAISE EXCEPTION 'Falta la asignatura: no se puede guardar sin ella';
  END IF;

  SELECT c.name, c.is_active INTO v_career_name, v_career_active
    FROM public.careers c WHERE c.id = NEW.career_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La carrera % no existe', NEW.career_id;
  END IF;

  IF NOT v_career_active THEN
    RAISE EXCEPTION
      'La carrera "%" está desactivada: no admite contenido nuevo',
      v_career_name;
  END IF;

  -- Materia propia de quien escribe: no tiene concepto de "activa" (es de
  -- uso personal del usuario, no del plan de estudios de una carrera).
  SELECT EXISTS (
    SELECT 1 FROM public.subjects sub
     WHERE sub.user_id = auth.uid()
       AND lower(btrim(sub.name)) = lower(btrim(NEW.subject))
  ) INTO v_ok;
  IF v_ok THEN RETURN NEW; END IF;

  -- Materia predefinida de la carrera, y si está activa.
  SELECT true, COALESCE((s->>'isActive')::boolean, true)
    INTO v_ok, v_subject_active
  FROM public.careers c,
       LATERAL jsonb_array_elements(c.predefined_subjects) AS s
  WHERE c.id = NEW.career_id
    AND lower(btrim(s->>'name')) = lower(btrim(NEW.subject))
  LIMIT 1;

  IF NOT COALESCE(v_ok, false) THEN
    RAISE EXCEPTION
      'La asignatura "%" no pertenece a la carrera "%"',
      NEW.subject, v_career_name;
  END IF;

  -- Solo tareas y reuniones exigen que además esté activa. study_files
  -- puede seguir clasificándose bajo una materia de un semestre anterior:
  -- es justo el caso que esto está pensado para permitir.
  IF TG_TABLE_NAME <> 'study_files' AND NOT v_subject_active THEN
    RAISE EXCEPTION
      'La asignatura "%" es de un semestre anterior: no admite tareas ni reuniones nuevas',
      NEW.subject;
  END IF;

  RETURN NEW;
END;
$$;

-- Verificación:
--
-- (a) Desactivar una materia predefinida y probar un INSERT en tasks o
--     meetings con esa materia: debe fallar con "semestre anterior".
-- (b) El mismo INSERT en study_files debe seguir funcionando.
-- (c) Una materia propia del usuario (tabla subjects) nunca debe verse
--     afectada por esto, esté como esté la predefinida del mismo nombre.
