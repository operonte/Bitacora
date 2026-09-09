-- Bitácora — directorio de la carrera: cualquier miembro (no solo docente
-- o admin) puede listar a sus compañeros para llegar a su perfil público.
--
-- admin_list_career_members (gestión de miembros) exige is_admin();
-- get_student_risk exige is_docente(). Este es el primero pensado para
-- cualquier miembro común, así que el único chequeo es "pertenecés a esta
-- carrera" — mismo patrón SECURITY DEFINER que el resto, sin política RLS
-- nueva sobre profiles ni user_careers.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_career_members(p_career_id TEXT)
RETURNS TABLE (
  user_id      UUID,
  display_name TEXT,
  photo_url    TEXT,
  role         TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.user_careers
     WHERE user_id = auth.uid() AND career_id = p_career_id
  ) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  RETURN QUERY
    SELECT p.id, p.display_name, p.photo_url, uc.role
      FROM public.user_careers uc
      JOIN public.profiles p ON p.id = uc.user_id
     WHERE uc.career_id = p_career_id
     ORDER BY uc.role DESC, p.display_name NULLS LAST;
END;
$$;

REVOKE ALL ON FUNCTION public.get_career_members(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_career_members(TEXT) TO authenticated;

COMMIT;
