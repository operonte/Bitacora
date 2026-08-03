-- ============================================================
-- BITÁCORA — Endurecimiento fase 2
--   1. Claves de carrera hasheadas y fuera del alcance del cliente
--   2. Membresías de carrera solo vía RPC que valida la clave
--   3. Auditoría de autoría en shared_tasks (quién creó / quién editó)
--
-- Requiere haber corrido supabase_hardening.sql antes (usa is_admin()).
-- Ejecutar completo en el SQL Editor. Idempotente.
--
-- IMPORTANTE: esta fase NO borra careers.access_key todavía, para que las
-- versiones viejas de la app instaladas por ahí sigan funcionando. El borrado
-- va en supabase_hardening_3_drop_access_key.sql, después de que todos
-- actualicen.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ─── 1. CLAVES DE CARRERA ────────────────────────────────────
-- access_key estaba en texto plano en una tabla de lectura abierta: cualquiera
-- con la anon key se llevaba las claves de todas las carreras. Ahora solo vive
-- el hash, en una tabla sin política de lectura para usuarios normales.

CREATE TABLE IF NOT EXISTS public.career_access_keys (
  career_id  TEXT PRIMARY KEY REFERENCES public.careers(id) ON DELETE CASCADE,
  key_hash   TEXT NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.career_access_keys ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "career_access_keys_admin" ON public.career_access_keys;
CREATE POLICY "career_access_keys_admin" ON public.career_access_keys
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
-- Los usuarios normales no tienen ninguna política: no leen ni escriben.
-- El único acceso es vía join_career(), que es SECURITY DEFINER.

-- careers.access_key es NOT NULL y la app ya no la manda en los INSERT. Sin
-- este default, crear una carrera desde el panel falla por violación de NOT
-- NULL. La columna se borra entera en la fase 3.
ALTER TABLE public.careers ALTER COLUMN access_key SET DEFAULT '';

-- La carrera predefinida 'teologia' vive en el código Dart, no en la base.
-- Sin fila acá, user_careers viola la llave foránea al registrar membresías.
INSERT INTO public.careers (id, name, access_key, description)
VALUES ('teologia', 'Teología', '', '')
ON CONFLICT (id) DO NOTHING;

-- Semilla de hashes: pasa las claves que ya existían en texto plano.
INSERT INTO public.career_access_keys (career_id, key_hash)
SELECT c.id, encode(extensions.digest(c.access_key, 'sha256'), 'hex')
FROM   public.careers c
WHERE  COALESCE(c.access_key, '') <> ''
ON CONFLICT (career_id) DO NOTHING;

-- Hash de la clave que estaba hardcodeada en career_model.dart y publicada
-- en el README. Se conserva a propósito para no dejar fuera a los usuarios
-- que ya la tienen. Para cambiarla: select public.set_career_access_key(...).
INSERT INTO public.career_access_keys (career_id, key_hash)
VALUES ('teologia', 'd96f0249104040d0dad2f222f3a89df1c61b29b6bc7c41d663a7be8eea7f40c7')
ON CONFLICT (career_id) DO NOTHING;

-- ─── 2. MEMBRESÍAS SOLO VÍA RPC ──────────────────────────────
-- Antes cualquiera se insertaba en cualquier carrera sin saber la clave: la
-- validación era solo del lado del cliente. Y como shared_tasks da acceso por
-- membresía, eso abría las tareas compartidas de cualquier carrera.

DROP POLICY IF EXISTS "user_careers_own"        ON public.user_careers;
DROP POLICY IF EXISTS "user_careers_select_own" ON public.user_careers;
DROP POLICY IF EXISTS "user_careers_delete_own" ON public.user_careers;

CREATE POLICY "user_careers_select_own" ON public.user_careers
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE POLICY "user_careers_delete_own" ON public.user_careers
  FOR DELETE TO authenticated USING (auth.uid() = user_id);
-- Sin política de INSERT ni UPDATE: crear una membresía pasa obligatoriamente
-- por join_career(), que valida la clave.

-- Devuelve el career_id si la clave es correcta, NULL si no lo es.
CREATE OR REPLACE FUNCTION public.join_career(p_access_key TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_career_id TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;

  IF COALESCE(p_access_key, '') = '' THEN
    RETURN NULL;
  END IF;

  SELECT k.career_id INTO v_career_id
  FROM   public.career_access_keys k
  WHERE  k.key_hash = encode(extensions.digest(p_access_key, 'sha256'), 'hex')
  LIMIT  1;

  IF v_career_id IS NULL THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.user_careers (user_id, career_id)
  VALUES (auth.uid(), v_career_id)
  ON CONFLICT (user_id, career_id) DO NOTHING;

  RETURN v_career_id;
END;
$$;

REVOKE ALL     ON FUNCTION public.join_career(TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.join_career(TEXT) TO authenticated;

-- Fija o cambia la clave de una carrera. Solo administradores.
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
  VALUES (p_career_id, encode(extensions.digest(p_access_key, 'sha256'), 'hex'), NOW())
  ON CONFLICT (career_id) DO UPDATE
    SET key_hash = EXCLUDED.key_hash, updated_at = NOW();
END;
$$;

REVOKE ALL     ON FUNCTION public.set_career_access_key(TEXT, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.set_career_access_key(TEXT, TEXT) TO authenticated;

-- ─── 3. AUTORÍA EN SHARED_TASKS ──────────────────────────────
-- Cualquier miembro de la carrera sigue pudiendo crear y editar tareas: eso es
-- a propósito. Lo que se agrega es el rastro de quién lo hizo. Los campos los
-- estampa un trigger, no el cliente, así que no se pueden falsear.

ALTER TABLE public.shared_tasks
  ADD COLUMN IF NOT EXISTS created_by_name TEXT,
  ADD COLUMN IF NOT EXISTS updated_by      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS updated_by_name TEXT,
  ADD COLUMN IF NOT EXISTS updated_at      TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.stamp_shared_task_author()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name TEXT;
BEGIN
  SELECT COALESCE(NULLIF(p.display_name, ''), p.email, '')
    INTO v_name
  FROM public.profiles p
  WHERE p.id = auth.uid();

  IF TG_OP = 'INSERT' THEN
    NEW.created_by      := auth.uid();
    NEW.created_by_name := COALESCE(v_name, '');
    NEW.updated_by      := NULL;
    NEW.updated_by_name := NULL;
    NEW.updated_at      := NULL;
  ELSE
    -- El creador original no se puede reescribir en un UPDATE.
    NEW.created_by      := OLD.created_by;
    NEW.created_by_name := OLD.created_by_name;
    NEW.updated_by      := auth.uid();
    NEW.updated_by_name := COALESCE(v_name, '');
    NEW.updated_at      := NOW();
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS shared_tasks_stamp_author ON public.shared_tasks;
CREATE TRIGGER shared_tasks_stamp_author
  BEFORE INSERT OR UPDATE ON public.shared_tasks
  FOR EACH ROW EXECUTE FUNCTION public.stamp_shared_task_author();

-- Rellena la autoría de creación en las filas que ya existen.
UPDATE public.shared_tasks s
SET    created_by_name = COALESCE(NULLIF(s.user_name, ''), 'Usuario desconocido')
WHERE  s.created_by_name IS NULL;

-- ─── 4. VERIFICACIÓN ─────────────────────────────────────────
-- (a) Ninguna política de escritura abierta. Debe dar 0 filas.
SELECT tablename, policyname, cmd
FROM   pg_policies
WHERE  schemaname = 'public' AND qual::text = 'true' AND cmd <> 'SELECT';

-- (b) Toda carrera debe tener su clave hasheada. Debe dar 0 filas.
SELECT c.id, c.name
FROM   public.careers c
LEFT   JOIN public.career_access_keys k ON k.career_id = c.id
WHERE  k.career_id IS NULL;
