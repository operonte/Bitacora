-- Bitácora — arregla un bug real reportado por el usuario probando la app:
-- "Miembros" de una carrera tiraba PostgrestException 42702 (columna
-- "user_id" ambigua) apenas se abría.
--
-- get_career_members declara RETURNS TABLE(user_id UUID, ...), y en
-- PL/pgSQL esas columnas de salida son variables visibles en todo el cuerpo
-- de la función. La comprobación de autorización usaba `user_id` sin
-- calificar contra user_careers, que también tiene una columna user_id:
-- Postgres no podía decidir si era la variable de salida o la columna de la
-- tabla. Se soluciona calificando la tabla con un alias.

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
    SELECT 1 FROM public.user_careers uc0
     WHERE uc0.user_id = auth.uid() AND uc0.career_id = p_career_id
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

COMMIT;
