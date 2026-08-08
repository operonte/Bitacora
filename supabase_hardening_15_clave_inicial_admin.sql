-- Bitácora — endurecimiento 15: contraseña inicial de un administrador nuevo
--
-- Falta que dejaba inservible al endurecimiento 14: nombrar a alguien
-- administrador le ponía `profiles.is_admin = TRUE` y nada más. Como
-- `verify_admin_password()` devuelve FALSE cuando no hay fila en
-- `admin_credentials`, esa persona quedaba con permiso y sin puerta:
--
--   · Era administradora para el servidor.
--   · No podía entrar al panel, porque no tenía contraseña.
--   · No podía crearse una, porque la única función que la define
--     (`set_admin_password`) se llama desde dentro del panel.
--
-- Se arregla dejando que quien nombra ponga también la contraseña inicial, y
-- se la comunique por fuera. Es el mismo gesto de dar de alta a alguien: das
-- el permiso y la llave a la vez.
--
-- La misma función sirve para reponerle la contraseña a un administrador que
-- la olvidó, que si no quedaba igual de bloqueado.

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_reset_password(
  p_user_id  UUID,
  p_password TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  IF p_password IS NULL OR length(p_password) < 8 THEN
    RAISE EXCEPTION 'La contraseña debe tener al menos 8 caracteres';
  END IF;

  -- Solo a quien ya tenga el permiso: si no, esto sería una forma de crear
  -- credenciales para cuentas cualesquiera.
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = p_user_id AND is_admin
  ) THEN
    RAISE EXCEPTION 'Esa cuenta no es administradora';
  END IF;

  INSERT INTO public.admin_credentials (user_id, password_hash, updated_at)
  VALUES (p_user_id, extensions.crypt(p_password, extensions.gen_salt('bf', 10)), NOW())
  ON CONFLICT (user_id) DO UPDATE
    SET password_hash   = EXCLUDED.password_hash,
        failed_attempts = 0,
        locked_until    = NULL,
        updated_at      = NOW();
END;
$$;

REVOKE ALL  ON FUNCTION public.admin_reset_password(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_reset_password(UUID, TEXT) TO authenticated;

-- Saber quién puede entrar de verdad. Un administrador sin contraseña tiene
-- el permiso pero no la puerta, y hasta ahora eso no se veía en ninguna parte.
--
-- Se agrega una columna al resultado, y Postgres no deja cambiar el tipo de
-- retorno con CREATE OR REPLACE: hay que borrarla y volver a crearla.
DROP FUNCTION IF EXISTS public.admin_list_admins();

CREATE FUNCTION public.admin_list_admins()
RETURNS TABLE (
  user_id      UUID,
  display_name TEXT,
  email        TEXT,
  has_password BOOLEAN
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
      p.id,
      p.display_name,
      p.email,
      EXISTS (SELECT 1 FROM public.admin_credentials c WHERE c.user_id = p.id)
      FROM public.profiles p
     WHERE p.is_admin
     ORDER BY p.display_name NULLS LAST;
END;
$$;

REVOKE ALL  ON FUNCTION public.admin_list_admins() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_admins() TO authenticated;

COMMIT;
