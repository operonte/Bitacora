-- ============================================================
-- BITÁCORA — Backfill de profiles y autoría con respaldo
--
-- El trigger on_auth_user_created crea la fila de profiles al registrarse,
-- pero las cuentas anteriores a ese trigger quedaron sin fila. Eso rompe dos
-- cosas: is_admin() siempre da false para esas cuentas, y la autoría de
-- shared_tasks sale en blanco porque no hay display_name que leer.
--
-- Ejecutar después de supabase_hardening_2.sql. Idempotente.
-- ============================================================

-- ─── 1. CREAR LAS FILAS QUE FALTAN ───────────────────────────
INSERT INTO public.profiles (id, display_name, email, photo_url)
SELECT u.id,
       COALESCE(u.raw_user_meta_data->>'full_name',
                u.raw_user_meta_data->>'name',
                ''),
       u.email,
       u.raw_user_meta_data->>'avatar_url'
FROM   auth.users u
LEFT   JOIN public.profiles p ON p.id = u.id
WHERE  p.id IS NULL
ON CONFLICT (id) DO NOTHING;

-- ─── 2. AUTORÍA CON RESPALDO ─────────────────────────────────
-- La versión anterior leía solo profiles.display_name. Si la fila no existía
-- o el nombre venía vacío, estampaba '' y la tarjeta mostraba "Editado por "
-- sin nombre. Ahora cae en cascada: display_name → email → 'Usuario'.
CREATE OR REPLACE FUNCTION public.stamp_shared_task_author()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name TEXT;
BEGIN
  SELECT COALESCE(NULLIF(TRIM(p.display_name), ''), NULLIF(TRIM(p.email), ''))
    INTO v_name
  FROM public.profiles p
  WHERE p.id = auth.uid();

  -- Sin fila en profiles: buscar el correo directamente en auth.users.
  IF v_name IS NULL THEN
    SELECT NULLIF(TRIM(u.email), '') INTO v_name
    FROM auth.users u WHERE u.id = auth.uid();
  END IF;

  v_name := COALESCE(v_name, 'Usuario');

  IF TG_OP = 'INSERT' THEN
    NEW.created_by      := auth.uid();
    NEW.created_by_name := v_name;
    NEW.updated_by      := NULL;
    NEW.updated_by_name := NULL;
    NEW.updated_at      := NULL;
  ELSE
    -- El creador original no se puede reescribir en un UPDATE.
    NEW.created_by      := OLD.created_by;
    NEW.created_by_name := OLD.created_by_name;
    NEW.updated_by      := auth.uid();
    NEW.updated_by_name := v_name;
    NEW.updated_at      := NOW();
  END IF;

  RETURN NEW;
END;
$$;

-- ─── 3. MANTENER SINCRONIZADO display_name ───────────────────
-- Si el usuario cambia su nombre en el proveedor de auth, la fila de profiles
-- se quedaba con el viejo. El trigger de creación solo corre en el INSERT.
CREATE OR REPLACE FUNCTION public.sync_profile_from_auth()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.profiles p
  SET    display_name = COALESCE(NULLIF(NEW.raw_user_meta_data->>'full_name', ''),
                                 NULLIF(NEW.raw_user_meta_data->>'name', ''),
                                 p.display_name),
         email        = COALESCE(NEW.email, p.email),
         photo_url    = COALESCE(NEW.raw_user_meta_data->>'avatar_url', p.photo_url)
  WHERE  p.id = NEW.id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_updated ON auth.users;
CREATE TRIGGER on_auth_user_updated
  AFTER UPDATE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.sync_profile_from_auth();

-- ─── 4. VERIFICACIÓN ─────────────────────────────────────────
-- Debe devolver 0.
SELECT COUNT(*) AS usuarios_sin_profile
FROM   auth.users u
LEFT   JOIN public.profiles p ON p.id = u.id
WHERE  p.id IS NULL;
