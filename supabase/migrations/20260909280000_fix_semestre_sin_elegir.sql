-- Bitácora — bug real: can_see_shared_subject_content dejaba a un alumno
-- que TODAVÍA NO ELIGIÓ SEMESTRE (el estado por defecto de cualquiera
-- recién unido a una carrera — nada en el alta se lo pide) sin ver NINGÚN
-- material docente compartido ni anuncio de una asignatura que sí tuviera
-- semestre cargado en el catálogo.
--
-- La comparación "uc.semester = v_semester" con uc.semester NULL da NULL
-- (ni true ni false) en SQL, así que el EXISTS nunca encontraba fila — se
-- degradaba a "no ve nada", no a "toda la carrera" como sí pasa cuando es
-- la MATERIA la que no tiene semestre cargado (ver comentario original de
-- la función, línea "si no, se degrada a cualquier miembro de la
-- carrera" — esa degradación faltaba para este otro caso). Sin ningún
-- aviso en la UI, se veía como "no hay material" cuando en realidad el
-- alumno estaba bloqueado por un dato que nunca se le pidió cargar.
--
-- Se unifica: el alumno ve el contenido si la materia no tiene semestre
-- cargado, O si el alumno no eligió el suyo todavía, O si coinciden.
-- Comparte función con material docente compartido y anuncios — se
-- corrige una sola vez para los dos.

BEGIN;

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

  RETURN EXISTS (
    SELECT 1 FROM public.user_careers uc
     WHERE uc.user_id = auth.uid()
       AND uc.career_id = p_career_id
       AND (
         v_semester IS NULL
         OR uc.semester IS NULL
         OR uc.semester = v_semester
       )
  );
END;
$$;

COMMIT;
