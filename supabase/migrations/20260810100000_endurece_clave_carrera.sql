-- Bitácora — endurece la clave de acceso a carreras
--
-- Dos huecos quedaban desde supabase_hardening_2:
--
--   1. join_career() no tenía freno: se podía probar la clave de una carrera
--      sin límite de intentos, a diferencia de verify_admin_password() (5
--      intentos / 15 min). Como las claves de carrera son cortas y pensadas
--      para compartirse de palabra, eran adivinables por fuerza bruta.
--   2. El hash era SHA-256 sin sal (encode(digest(...,'sha256'),'hex')). Un
--      volcado de career_access_keys se rompe con una tabla arcoíris en
--      milisegundos. admin_credentials ya usa bcrypt (pgcrypto); acá se
--      alinea al mismo estándar.
--
-- No se puede recalcular bcrypt sobre las claves existentes sin conocer el
-- texto plano, así que la migración no las reescribe de una: join_career()
-- sigue aceptando el hash SHA-256 viejo, y en cuanto alguien entra con éxito
-- lo sube a bcrypt ahí mismo. Las claves nuevas (set_career_access_key) ya
-- salen en bcrypt desde ahora. Con el tiempo, toda clave activa termina
-- migrada sin que nadie tenga que rotarla a mano.

BEGIN;

-- ─── 1. INTENTOS FALLIDOS POR USUARIO ────────────────────────
-- Mismo patrón que admin_credentials: sin políticas (RLS activo, nadie entra
-- salvo las funciones SECURITY DEFINER de abajo).

CREATE TABLE IF NOT EXISTS public.career_join_attempts (
  user_id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  failed_attempts INT         NOT NULL DEFAULT 0,
  locked_until    TIMESTAMPTZ,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.career_join_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.career_join_attempts FROM anon, authenticated;

-- ─── 2. join_career() CON BLOQUEO Y UPGRADE A BCRYPT ─────────

CREATE OR REPLACE FUNCTION public.join_career(p_access_key TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_career_id TEXT;
  v_key_hash  TEXT;
  v_locked    TIMESTAMPTZ;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;

  SELECT locked_until INTO v_locked
    FROM public.career_join_attempts
   WHERE user_id = auth.uid();

  IF v_locked IS NOT NULL AND v_locked > NOW() THEN
    RAISE EXCEPTION 'Demasiados intentos. Probá de nuevo en unos minutos.';
  END IF;

  IF COALESCE(p_access_key, '') = '' THEN
    RETURN NULL;
  END IF;

  -- El CASE evita llamar crypt() con un "salt" que en realidad es un hash
  -- SHA-256 viejo: crypt() lanza error si el salt no tiene formato bcrypt, y
  -- un OR normal no garantiza qué lado se evalúa primero en Postgres.
  SELECT k.career_id, k.key_hash INTO v_career_id, v_key_hash
  FROM   public.career_access_keys k
  WHERE  k.key_hash = CASE
           WHEN k.key_hash LIKE '$2%'
             THEN extensions.crypt(p_access_key, k.key_hash)
           ELSE encode(extensions.digest(p_access_key, 'sha256'), 'hex')
         END
  LIMIT  1;

  IF v_career_id IS NULL THEN
    INSERT INTO public.career_join_attempts (user_id, failed_attempts, locked_until)
    VALUES (auth.uid(), 1, NULL)
    ON CONFLICT (user_id) DO UPDATE
      SET failed_attempts = career_join_attempts.failed_attempts + 1,
          locked_until = CASE
            WHEN career_join_attempts.failed_attempts + 1 >= 5
              THEN NOW() + INTERVAL '15 minutes'
            ELSE career_join_attempts.locked_until
          END,
          updated_at = NOW();
    RETURN NULL;
  END IF;

  DELETE FROM public.career_join_attempts WHERE user_id = auth.uid();

  -- Éxito con un hash todavía en formato viejo: se sube a bcrypt de una vez.
  IF v_key_hash NOT LIKE '$2%' THEN
    UPDATE public.career_access_keys
       SET key_hash   = extensions.crypt(p_access_key, extensions.gen_salt('bf', 10)),
           updated_at = NOW()
     WHERE career_id = v_career_id;
  END IF;

  INSERT INTO public.user_careers (user_id, career_id)
  VALUES (auth.uid(), v_career_id)
  ON CONFLICT (user_id, career_id) DO NOTHING;

  RETURN v_career_id;
END;
$$;

REVOKE ALL     ON FUNCTION public.join_career(TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.join_career(TEXT) TO authenticated;

-- ─── 3. set_career_access_key() YA SALE EN BCRYPT ────────────

CREATE OR REPLACE FUNCTION public.set_career_access_key(
  p_career_id TEXT,
  p_access_key TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Solo administradores pueden cambiar la clave de una carrera';
  END IF;

  IF COALESCE(p_access_key, '') = '' THEN
    RAISE EXCEPTION 'La clave de acceso no puede estar vacía';
  END IF;

  INSERT INTO public.career_access_keys (career_id, key_hash, updated_at)
  VALUES (
    p_career_id,
    extensions.crypt(p_access_key, extensions.gen_salt('bf', 10)),
    NOW()
  )
  ON CONFLICT (career_id) DO UPDATE
    SET key_hash = EXCLUDED.key_hash, updated_at = NOW();
END;
$$;

REVOKE ALL     ON FUNCTION public.set_career_access_key(TEXT, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.set_career_access_key(TEXT, TEXT) TO authenticated;

COMMIT;

-- Verificación:
--
-- (a) Nadie debería poder leer los intentos ajenos. Debe dar 0 filas.
-- SELECT * FROM public.career_join_attempts; -- (con la anon/authenticated key)
--
-- (b) Tras 5 fallos seguidos con la misma cuenta, join_career debe tirar
--     'Demasiados intentos...' aunque la clave sea correcta.
--
-- (c) Tras unirse con éxito a una carrera cuya clave todavía estaba en
--     SHA-256, career_access_keys.key_hash debe empezar con '$2'.
