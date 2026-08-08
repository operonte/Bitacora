-- Bitácora — endurecimiento 14: gestión de miembros y de administradores
--
-- Hasta ahora dos cosas solo se podían hacer escribiendo SQL a mano:
--
--   · Ver quién pertenece a una carrera, y sacar a alguien.
--   · Dar o quitar el permiso de administrador.
--
-- Lo segundo importa más de lo que parece: `profiles.is_admin` es la única
-- llave del panel, y el GRANT de UPDATE sobre `profiles` la deja fuera a
-- propósito, así que ni el propio dueño podía nombrar a un suplente desde la
-- app. Si perdía el acceso a esa cuenta, se quedaba fuera.
--
-- Todo pasa por funciones SECURITY DEFINER que empiezan comprobando
-- `is_admin()`. No se abre ninguna política nueva sobre las tablas: si mañana
-- alguien se salta la app y llama al API directo, sigue sin poder leer
-- `profiles` ajenos ni tocar `user_careers` de otros.

BEGIN;

-- ── Miembros de una carrera ──────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_list_career_members(p_career_id TEXT)
RETURNS TABLE (
  user_id      UUID,
  display_name TEXT,
  email        TEXT,
  is_admin     BOOLEAN,
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
    SELECT p.id, p.display_name, p.email, p.is_admin, uc.joined_at
      FROM public.user_careers uc
      JOIN public.profiles p ON p.id = uc.user_id
     WHERE uc.career_id = p_career_id
     ORDER BY p.display_name NULLS LAST;
END;
$$;

-- Cuánto se lleva por delante borrar una carrera. La app lo muestra antes de
-- pedir confirmación: `user_careers` borra en cascada, así que eliminar una
-- carrera expulsa a todos sus miembros de una vez.
CREATE OR REPLACE FUNCTION public.admin_career_impact(p_career_id TEXT)
RETURNS TABLE (
  members  BIGINT,
  tasks    BIGINT,
  meetings BIGINT,
  files    BIGINT
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
    SELECT
      (SELECT count(*) FROM public.user_careers WHERE career_id = p_career_id),
      (SELECT count(*) FROM public.shared_tasks WHERE career_id = p_career_id),
      (SELECT count(*) FROM public.meetings     WHERE career_id = p_career_id),
      (SELECT count(*) FROM public.study_files  WHERE career_id = p_career_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_remove_member(
  p_career_id TEXT,
  p_user_id   UUID
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

  DELETE FROM public.user_careers
   WHERE career_id = p_career_id AND user_id = p_user_id;
END;
$$;

-- ── Administradores ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.admin_list_admins()
RETURNS TABLE (
  user_id      UUID,
  display_name TEXT,
  email        TEXT
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
    SELECT p.id, p.display_name, p.email
      FROM public.profiles p
     WHERE p.is_admin
     ORDER BY p.display_name NULLS LAST;
END;
$$;

-- Busca una cuenta por correo para poder nombrarla administradora. Devuelve
-- como máximo una fila y solo para un administrador: no sirve para enumerar
-- usuarios.
CREATE OR REPLACE FUNCTION public.admin_find_user(p_email TEXT)
RETURNS TABLE (
  user_id      UUID,
  display_name TEXT,
  email        TEXT,
  is_admin     BOOLEAN
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
    SELECT p.id, p.display_name, p.email, p.is_admin
      FROM public.profiles p
     WHERE lower(p.email) = lower(trim(p_email))
     LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_admin(
  p_user_id  UUID,
  p_is_admin BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_restantes INT;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  -- Quitarse el permiso a uno mismo deja el panel sin dueño y sin forma de
  -- recuperarlo desde la app: habría que volver al SQL a mano, que es
  -- justamente lo que esto viene a evitar.
  IF p_user_id = auth.uid() AND NOT p_is_admin THEN
    RAISE EXCEPTION 'No puedes quitarte a ti mismo el permiso de administrador';
  END IF;

  -- Red de seguridad por si algún día la comprobación de arriba se puede
  -- rodear: nunca dejar la instalación sin ningún administrador.
  IF NOT p_is_admin THEN
    SELECT count(*) INTO v_restantes
      FROM public.profiles
     WHERE is_admin AND id <> p_user_id;

    IF v_restantes = 0 THEN
      RAISE EXCEPTION 'Debe quedar al menos un administrador';
    END IF;
  END IF;

  UPDATE public.profiles SET is_admin = p_is_admin WHERE id = p_user_id;

  -- Sin permiso no hace falta contraseña de panel.
  IF NOT p_is_admin THEN
    DELETE FROM public.admin_credentials WHERE user_id = p_user_id;
  END IF;
END;
$$;

-- ── Permisos ─────────────────────────────────────────────────────────────

REVOKE ALL ON FUNCTION public.admin_list_career_members(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_career_impact(TEXT)       FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_remove_member(TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_list_admins()             FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_find_user(TEXT)           FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_set_admin(UUID, BOOLEAN)  FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_list_career_members(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_career_impact(TEXT)       TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_remove_member(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_admins()             TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_find_user(TEXT)           TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_admin(UUID, BOOLEAN)  TO authenticated;

COMMIT;
