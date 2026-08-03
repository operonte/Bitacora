-- ============================================================
-- BITÁCORA — Endurecimiento de RLS
-- Ejecutar completo en el SQL Editor de Supabase.
-- Idempotente: se puede correr más de una vez sin romper nada.
-- ============================================================

-- ─── 1. FLAG DE ADMIN NO ESCRIBIBLE POR EL USUARIO ───────────
-- Antes el "admin" se deducía de admin_password_hash, pero el usuario
-- puede escribir su propia fila de profiles, así que cualquiera podía
-- ascenderse solo. El flag va en una columna aparte sin permiso de
-- escritura para anon/authenticated.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_admin BOOLEAN NOT NULL DEFAULT FALSE;

-- El privilegio de tabla domina sobre el de columna, así que hay que
-- quitar UPDATE completo y volver a otorgarlo solo en las columnas
-- que el usuario sí debe poder cambiar. is_admin queda fuera.
REVOKE UPDATE ON public.profiles FROM anon, authenticated;
GRANT  UPDATE (display_name, email, photo_url, admin_password_hash)
  ON public.profiles TO authenticated;

-- Helper. SECURITY DEFINER evita recursión de RLS al consultar
-- profiles desde las políticas de otras tablas.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE((SELECT p.is_admin FROM public.profiles p WHERE p.id = auth.uid()), FALSE);
$$;

REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

-- ─── 2. PROFILES ─────────────────────────────────────────────
-- La política vieja era FOR ALL USING (auth.uid() = id) sin WITH CHECK.
DROP POLICY IF EXISTS "profiles_own"        ON public.profiles;
DROP POLICY IF EXISTS "profiles_select_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_insert_own" ON public.profiles;
DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;

CREATE POLICY "profiles_select_own" ON public.profiles
  FOR SELECT TO authenticated USING (auth.uid() = id);

CREATE POLICY "profiles_insert_own" ON public.profiles
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);
-- Sin política de DELETE: nadie borra filas de profiles desde el cliente.

-- ─── 3. CAREERS ──────────────────────────────────────────────
-- Antes: FOR ALL USING (true) WITH CHECK (true) — cualquiera con la
-- anon key podía borrar todas las carreras sin estar logueado.
DROP POLICY IF EXISTS "careers_public_all"  ON public.careers;
DROP POLICY IF EXISTS "careers_read"        ON public.careers;
DROP POLICY IF EXISTS "careers_all"         ON public.careers;
DROP POLICY IF EXISTS "careers_write"       ON public.careers;
DROP POLICY IF EXISTS "careers_admin_write" ON public.careers;

-- Lectura abierta: la pantalla de selección de carrera corre antes del login.
CREATE POLICY "careers_read" ON public.careers
  FOR SELECT TO anon, authenticated USING (true);

CREATE POLICY "careers_admin_write" ON public.careers
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ─── 4. STUDY_FILES ──────────────────────────────────────────
-- Antes: FOR ALL USING (true) WITH CHECK (true) — cualquiera leía y
-- borraba los metadatos de archivos de todos, incluido drive_link.
-- Ojo: study_files.user_id es TEXT, no UUID. De ahí el cast.
DROP POLICY IF EXISTS "study_files_public_all" ON public.study_files;
DROP POLICY IF EXISTS "study_files_own"        ON public.study_files;

CREATE POLICY "study_files_own" ON public.study_files
  FOR ALL TO authenticated
  USING (user_id = auth.uid()::text)
  WITH CHECK (user_id = auth.uid()::text);

-- ─── 5. VERIFICACIÓN ─────────────────────────────────────────
-- Debe devolver 0 filas. Si aparece alguna, esa tabla sigue abierta.
SELECT schemaname, tablename, policyname, cmd, qual::text
FROM   pg_policies
WHERE  schemaname = 'public'
  AND  qual::text = 'true'
  AND  cmd <> 'SELECT';
