-- Bitácora — el admin puede moderar lo que un docente publica.
--
-- announcements_delete hoy solo deja borrar al creador. Un admin no tiene
-- forma de bajar un anuncio inapropiado sin entrar a la base a mano. RPC
-- SECURITY DEFINER, mismo patrón que el resto de admin_*: no se toca la
-- política existente, se agrega una puerta more por encima.

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_delete_announcement(p_announcement_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  DELETE FROM public.announcements WHERE id = p_announcement_id;
END;
$$;

-- Quiénes dictan qué en una carrera, para el panel de administración —
-- hoy hay que ir miembro por miembro para verlo.
CREATE OR REPLACE FUNCTION public.admin_list_teaching_assignments(p_career_id TEXT)
RETURNS TABLE (
  user_id      UUID,
  display_name TEXT,
  email        TEXT,
  subject      TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  RETURN QUERY
    SELECT p.id, p.display_name, p.email, ts.subject
      FROM public.teacher_subjects ts
      JOIN public.profiles p ON p.id = ts.user_id
     WHERE ts.career_id = p_career_id
     ORDER BY p.display_name NULLS LAST, ts.subject;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_announcement(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_teaching_assignments(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_announcement(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_teaching_assignments(TEXT) TO authenticated;

COMMIT;
