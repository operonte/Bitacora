-- Bitácora — endurecimiento 13: segundo factor del panel de administración
--
-- Entrar al panel pasa a exigir DOS cosas:
--   1. Estar autenticado con una cuenta que tenga profiles.is_admin = TRUE.
--   2. Escribir una contraseña de administrador.
--
-- Diferencias con la contraseña maestra que se eliminó en el endurecimiento 12:
--
--   · No está en el código. El hash vive acá y nunca se descarga al cliente:
--     la tabla tiene RLS que niega todo, y lo único que la toca son las
--     funciones SECURITY DEFINER de más abajo.
--   · Es por usuario, no compartida. Quitarle el acceso a alguien no obliga a
--     rotarle la clave a todo el mundo.
--   · Es bcrypt con sal (pgcrypto), no un SHA-256 pelado. Un volcado de la
--     tabla no se rompe con una tabla arcoíris.
--   · La comparación ocurre en el servidor. La versión anterior comparaba en
--     el cliente, así que bastaba parchear el APK para saltársela.
--
-- La contraseña NO se define en este script a propósito: se escribe una sola
-- vez desde la app, que llama a set_admin_password(). Ponerla acá la dejaría
-- en texto plano dentro de un archivo versionado, que es exactamente cómo se
-- filtró la anterior.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ── Tabla de credenciales ────────────────────────────────────────────────
--
-- Separada de `profiles` porque profiles se puede leer: cualquier política
-- que abra esa tabla expondría el hash. Ésta no la lee nadie.

CREATE TABLE IF NOT EXISTS public.admin_credentials (
  user_id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  password_hash   TEXT        NOT NULL,
  failed_attempts INT         NOT NULL DEFAULT 0,
  locked_until    TIMESTAMPTZ,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.admin_credentials ENABLE ROW LEVEL SECURITY;

-- Sin políticas: con RLS activo y ninguna política, nadie pasa. Las funciones
-- de abajo son SECURITY DEFINER, así que entran igual.
REVOKE ALL ON public.admin_credentials FROM anon, authenticated;

-- ── ¿Ya hay contraseña definida? ─────────────────────────────────────────
--
-- La app lo pregunta para saber si pedir la contraseña o pedir que se cree.
-- No filtra nada: solo dice si existe una fila para quien pregunta.

CREATE OR REPLACE FUNCTION public.admin_password_is_set()
RETURNS BOOLEAN
LANGUAGE SQL
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.admin_credentials WHERE user_id = auth.uid()
  );
$$;

-- ── Definir o cambiar la contraseña ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.set_admin_password(p_password TEXT)
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

  INSERT INTO public.admin_credentials (user_id, password_hash, updated_at)
  VALUES (auth.uid(), extensions.crypt(p_password, extensions.gen_salt('bf', 10)), NOW())
  ON CONFLICT (user_id) DO UPDATE
    SET password_hash   = EXCLUDED.password_hash,
        failed_attempts = 0,
        locked_until    = NULL,
        updated_at      = NOW();
END;
$$;

-- ── Verificar la contraseña ──────────────────────────────────────────────
--
-- Cuenta los intentos fallidos y bloquea 15 minutos a los 5. Acá el límite sí
-- sirve, a diferencia del que tenía la versión anterior: como la comparación
-- pasa por el servidor, no se puede evitar parcheando la app.

CREATE OR REPLACE FUNCTION public.verify_admin_password(p_password TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_cred  public.admin_credentials%ROWTYPE;
  v_ok    BOOLEAN;
BEGIN
  -- Sin el flag no hay nada que verificar: la contraseña sola no da acceso.
  IF NOT public.is_admin() THEN
    RETURN FALSE;
  END IF;

  SELECT * INTO v_cred
    FROM public.admin_credentials
   WHERE user_id = auth.uid();

  IF NOT FOUND THEN
    RETURN FALSE;
  END IF;

  IF v_cred.locked_until IS NOT NULL AND v_cred.locked_until > NOW() THEN
    RETURN FALSE;
  END IF;

  v_ok := (v_cred.password_hash = extensions.crypt(p_password, v_cred.password_hash));

  IF v_ok THEN
    UPDATE public.admin_credentials
       SET failed_attempts = 0, locked_until = NULL
     WHERE user_id = auth.uid();
  ELSE
    UPDATE public.admin_credentials
       SET failed_attempts = failed_attempts + 1,
           locked_until = CASE
             WHEN failed_attempts + 1 >= 5 THEN NOW() + INTERVAL '15 minutes'
             ELSE locked_until
           END
     WHERE user_id = auth.uid();
  END IF;

  RETURN v_ok;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_password_is_set()          FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_admin_password(TEXT)         FROM PUBLIC;
REVOKE ALL ON FUNCTION public.verify_admin_password(TEXT)      FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.admin_password_is_set()      TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_admin_password(TEXT)     TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_admin_password(TEXT)  TO authenticated;

COMMIT;

-- Verificación:
--
-- SELECT public.admin_password_is_set();      -- FALSE hasta definirla en la app
-- SELECT id, email, is_admin FROM public.profiles WHERE is_admin;
