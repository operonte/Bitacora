-- El perfil público de un docente no decía qué imparte. Cualquier miembro de
-- la carrera ya puede ver el directorio completo (get_career_members) y
-- quién es docente ahí; esto suma el detalle de qué asignaturas, mismo nivel
-- de exposición (compartir la carrera alcanza, no hace falta ser docente
-- para consultarlo).
CREATE OR REPLACE FUNCTION public.get_teacher_subjects_for(p_career_id text, p_teacher_id uuid)
RETURNS TABLE(subject text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.user_careers uc
     WHERE uc.user_id = auth.uid() AND uc.career_id = p_career_id
  ) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  RETURN QUERY
    SELECT ts.subject FROM public.teacher_subjects ts
     WHERE ts.career_id = p_career_id AND ts.user_id = p_teacher_id
     ORDER BY ts.subject;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_teacher_subjects_for(text, uuid) TO authenticated;
