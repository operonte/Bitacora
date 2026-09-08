-- Bitácora — cómo se cruzan alumno y docente por asignatura.
--
-- En la práctica (según lo explicado): un docente elige qué asignaturas
-- imparte; un alumno elige en qué semestre/trimestre está. `subjects.semester`
-- ya existe desde la carga de mallas curriculares (v2.10.0) y ya etiqueta
-- cada materia con su semestre — solo hacía falta que el ALUMNO también
-- tuviera uno, para poder cruzarlos. No se creó una tabla "cursos" aparte:
-- reutiliza exactamente el mismo campo que ya usa el catálogo, evitando dos
-- fuentes de verdad para la misma idea.
--
-- Si una materia no tiene semestre cargado (pasa en carreras chicas, según
-- el comentario de career_subjects_screen.dart), se degrada a compartir con
-- toda la carrera — el comportamiento de hoy, no uno peor.

BEGIN;

ALTER TABLE public.user_careers
  ADD COLUMN IF NOT EXISTS semester TEXT;

-- El alumno elige su propio semestre — no hace falta admin. Cualquiera puede
-- cambiar el suyo dentro de una carrera a la que ya pertenece.
CREATE OR REPLACE FUNCTION public.set_my_semester(p_career_id TEXT, p_semester TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.user_careers
     SET semester = NULLIF(trim(p_semester), '')
   WHERE user_id = auth.uid() AND career_id = p_career_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No perteneces a esa carrera';
  END IF;
END;
$$;

-- Qué asignaturas imparte cada docente. Por nombre, no por id: en el resto
-- de la app (tareas, reuniones, archivos) la asignatura ya es un texto libre
-- copiado del catálogo, no una referencia — se mantiene la misma convención
-- en vez de sumar una inconsistencia nueva.
CREATE TABLE IF NOT EXISTS public.teacher_subjects (
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  career_id   TEXT NOT NULL REFERENCES public.careers(id) ON DELETE CASCADE,
  subject     TEXT NOT NULL,
  PRIMARY KEY (user_id, career_id, subject)
);

ALTER TABLE public.teacher_subjects ENABLE ROW LEVEL SECURITY;
-- Sin políticas propias: todo pasa por los RPC de abajo, mismo patrón que
-- attendance y admin_credentials.

CREATE OR REPLACE FUNCTION public.set_teaching_subject(
  p_career_id TEXT,
  p_subject   TEXT,
  p_teaching  BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_docente(p_career_id) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  IF p_teaching THEN
    INSERT INTO public.teacher_subjects (user_id, career_id, subject)
    VALUES (auth.uid(), p_career_id, p_subject)
    ON CONFLICT DO NOTHING;
  ELSE
    DELETE FROM public.teacher_subjects
     WHERE user_id = auth.uid() AND career_id = p_career_id AND subject = p_subject;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_my_teaching_subjects(p_career_id TEXT)
RETURNS TABLE (subject TEXT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT ts.subject
    FROM public.teacher_subjects ts
   WHERE ts.user_id = auth.uid() AND ts.career_id = p_career_id;
$$;

-- Semestre de una asignatura del catálogo, o NULL si no está cargado.
--
-- El catálogo de materias de una carrera no vive en la tabla `subjects`
-- (esa es la lista personal de cada alumno, sin career_id ni semestre):
-- vive en `careers.predefined_subjects`, un JSONB con un objeto por materia
-- —el mismo que arma Subject.toMap() en el cliente— cargado por las
-- migraciones de mallas curriculares (carga_materias_*.sql).
CREATE OR REPLACE FUNCTION public.subject_semester(p_career_id TEXT, p_subject TEXT)
RETURNS TEXT
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT elem->>'semester'
    FROM public.careers c
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(c.predefined_subjects, '[]'::jsonb)) AS elem
   WHERE c.id = p_career_id
     AND elem->>'name' = p_subject
     AND elem->>'semester' IS NOT NULL
   LIMIT 1;
$$;

-- El cruce en sí: puede auth.uid() ver contenido de [p_subject] en
-- [p_career_id]. Coincide el semestre si la materia tiene uno cargado; si
-- no, se degrada a "cualquier miembro de la carrera".
CREATE OR REPLACE FUNCTION public.can_see_shared_subject_content(p_career_id TEXT, p_subject TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_semester TEXT;
BEGIN
  v_semester := public.subject_semester(p_career_id, p_subject);

  IF v_semester IS NULL THEN
    RETURN EXISTS (
      SELECT 1 FROM public.user_careers uc
       WHERE uc.user_id = auth.uid() AND uc.career_id = p_career_id
    );
  END IF;

  RETURN EXISTS (
    SELECT 1 FROM public.user_careers uc
     WHERE uc.user_id = auth.uid() AND uc.career_id = p_career_id
       AND uc.semester = v_semester
  );
END;
$$;

-- Asistencia también se acota por semestre cuando la materia lo tiene
-- cargado: es la otra herramienta que más usan los docentes, según lo
-- conversado, y merece la misma precisión que el material.
CREATE OR REPLACE FUNCTION public.get_attendance_roster(
  p_career_id  TEXT,
  p_subject    TEXT,
  p_class_date DATE
)
RETURNS TABLE (
  user_id      UUID,
  display_name TEXT,
  email        TEXT,
  status       TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_semester TEXT;
BEGIN
  IF NOT public.is_docente(p_career_id) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  v_semester := public.subject_semester(p_career_id, p_subject);

  RETURN QUERY
    SELECT p.id, p.display_name, p.email,
           COALESCE(a.status, 'sin_marcar')
      FROM public.user_careers uc
      JOIN public.profiles p ON p.id = uc.user_id
      LEFT JOIN public.attendance a
             ON a.career_id = p_career_id AND a.subject = p_subject
            AND a.class_date = p_class_date AND a.user_id = uc.user_id
     WHERE uc.career_id = p_career_id
       AND (v_semester IS NULL OR uc.semester = v_semester)
     ORDER BY p.display_name NULLS LAST;
END;
$$;

REVOKE ALL ON FUNCTION public.set_my_semester(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_teaching_subject(TEXT, TEXT, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_my_teaching_subjects(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.subject_semester(TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_see_shared_subject_content(TEXT, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.set_my_semester(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_teaching_subject(TEXT, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_teaching_subjects(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.subject_semester(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_see_shared_subject_content(TEXT, TEXT) TO authenticated;

COMMIT;
