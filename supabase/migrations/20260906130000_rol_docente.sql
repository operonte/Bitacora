-- Bitácora — Fase 0 del ecosistema docente: reconocer quién es docente.
--
-- Hasta ahora "quién puede hacer X" en una tarea o reunión se resolvía por
-- "quién la creó" — funciona, pero no da una identidad estable ("soy
-- docente de esta carrera") que las próximas fases (tareas oficiales,
-- asistencia, anuncios) necesitan para decidir permisos sin depender de
-- quién tocó qué primero.
--
-- Se agrega como una columna en user_careers, no una tabla nueva: el rol es
-- por persona y por carrera (alguien puede ser docente en una carrera y
-- estudiante en otra). Solo un admin lo asigna, vía RPC SECURITY DEFINER —
-- mismo patrón que admin_set_admin en supabase_hardening_14. No se abre
-- ninguna política nueva sobre user_careers: seguir gestionando el rol por
-- fuera de la app sigue exigiendo ser admin.

BEGIN;

ALTER TABLE public.user_careers
  ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'estudiante';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'user_careers_role_chk'
  ) THEN
    ALTER TABLE public.user_careers
      ADD CONSTRAINT user_careers_role_chk CHECK (role IN ('estudiante', 'docente'));
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.admin_set_member_role(
  p_career_id TEXT,
  p_user_id   UUID,
  p_role      TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  IF p_role NOT IN ('estudiante', 'docente') THEN
    RAISE EXCEPTION 'Rol inválido: %', p_role;
  END IF;

  UPDATE public.user_careers
     SET role = p_role
   WHERE career_id = p_career_id AND user_id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Esa persona no pertenece a la carrera';
  END IF;
END;
$$;

-- admin_list_career_members ahora también informa el rol, para que el panel
-- de miembros pueda mostrarlo y ofrecer el cambio sin una segunda consulta.
-- Cambia el tipo de fila (OUT params), así que hay que borrarla antes: un
-- CREATE OR REPLACE no puede cambiar la forma del resultado.
DROP FUNCTION IF EXISTS public.admin_list_career_members(TEXT);

CREATE FUNCTION public.admin_list_career_members(p_career_id TEXT)
RETURNS TABLE (
  user_id      UUID,
  display_name TEXT,
  email        TEXT,
  is_admin     BOOLEAN,
  role         TEXT,
  joined_at    TIMESTAMPTZ
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
    SELECT p.id, p.display_name, p.email, p.is_admin, uc.role, uc.joined_at
      FROM public.user_careers uc
      JOIN public.profiles p ON p.id = uc.user_id
     WHERE uc.career_id = p_career_id
     ORDER BY p.display_name NULLS LAST;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_member_role(TEXT, UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_member_role(TEXT, UUID, TEXT) TO authenticated;

COMMIT;
