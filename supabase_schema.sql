-- ============================================================
-- BITÁCORA — Esquema PostgreSQL para Supabase
-- Pegar en: supabase.com/dashboard/project/pigrmmxmcmtdppkhnsbw/sql/new
--
-- Este archivo deja las tablas y las políticas base. Después hay que correr,
-- en este orden:
--   1. supabase_hardening.sql    — flag is_admin(), políticas de escritura
--   2. supabase_hardening_2.sql  — claves de carrera hasheadas, RPC
--                                  join_career(), auditoría de shared_tasks
--   3. supabase_hardening_3_drop_access_key.sql — DIFERIDO, leer el archivo
--
-- Regla que se rompió una vez y no hay que volver a romper: ninguna política
-- de escritura puede ser USING (true). La anon key viaja dentro de cada APK,
-- así que USING (true) equivale a dejar la tabla abierta a internet.
-- ============================================================

-- ─── PROFILES (extensión de auth.users) ─────────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
  id                  UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name        TEXT,
  email               TEXT,
  photo_url           TEXT,
  admin_password_hash TEXT,
  -- Flag de administrador. NO se deduce de admin_password_hash: el usuario
  -- puede escribir su propia fila, así que usar ese campo como señal de
  -- privilegio permite que cualquiera se ascienda solo. Ver el REVOKE de
  -- más abajo, que impide escribir esta columna desde el cliente.
  is_admin            BOOLEAN NOT NULL DEFAULT FALSE,
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

-- El privilegio de tabla domina sobre el de columna: hay que quitar UPDATE
-- completo y reotorgarlo solo en las columnas que el usuario sí puede tocar.
REVOKE UPDATE ON public.profiles FROM anon, authenticated;
GRANT  UPDATE (display_name, email, photo_url, admin_password_hash)
  ON public.profiles TO authenticated;

-- SECURITY DEFINER evita recursión de RLS al consultar profiles desde
-- las políticas de otras tablas.
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT COALESCE((SELECT p.is_admin FROM public.profiles p WHERE p.id = auth.uid()), FALSE);
$$;

REVOKE ALL     ON FUNCTION public.is_admin() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.is_admin() TO authenticated;

-- Trigger: crea profile automáticamente al registrarse un usuario
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name, email, photo_url)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', ''),
    NEW.email,
    NEW.raw_user_meta_data->>'avatar_url'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ─── CAREERS ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.careers (
  id                  TEXT PRIMARY KEY,
  name                TEXT NOT NULL,
  -- OBSOLETA. La clave real vive hasheada en career_access_keys (ver
  -- supabase_hardening_2.sql). Esta columna queda solo para que las apps
  -- viejas no crasheen y se borra en la fase 3. No escribir nada acá.
  access_key          TEXT NOT NULL DEFAULT '',
  description         TEXT DEFAULT '',
  predefined_subjects JSONB DEFAULT '[]'::jsonb,
  created_at          TIMESTAMPTZ DEFAULT NOW(),
  updated_at          TIMESTAMPTZ DEFAULT NOW()
);

-- ─── USER_CAREERS (membresías usuario-carrera) ───────────────
CREATE TABLE IF NOT EXISTS public.user_careers (
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  career_id  TEXT NOT NULL REFERENCES public.careers(id) ON DELETE CASCADE,
  joined_at  TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (user_id, career_id)
);

-- ─── SUBJECTS (materias personales del usuario) ──────────────
CREATE TABLE IF NOT EXISTS public.subjects (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name          TEXT NOT NULL,
  professor     TEXT NOT NULL,
  description   TEXT,
  visibility    INT DEFAULT 0,
  allowed_users TEXT[] DEFAULT '{}',
  user_name     TEXT NOT NULL DEFAULT '',
  created_at    BIGINT NOT NULL
);

-- ─── TASKS (tareas personales) ───────────────────────────────
CREATE TABLE IF NOT EXISTS public.tasks (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title         TEXT NOT NULL,
  description   TEXT NOT NULL,
  subject       TEXT NOT NULL,
  professor     TEXT NOT NULL,
  due_date      BIGINT NOT NULL,
  is_completed  BOOLEAN DEFAULT FALSE,
  is_submitted  BOOLEAN DEFAULT FALSE,
  type          TEXT DEFAULT 'trabajo',
  created_at    BIGINT NOT NULL,
  tag           TEXT,
  user_name     TEXT NOT NULL DEFAULT '',
  career_id     TEXT,
  collaborators TEXT[] DEFAULT '{}'
);

-- ─── SHARED_TASKS (tareas compartidas por carrera) ───────────
CREATE TABLE IF NOT EXISTS public.shared_tasks (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  career_id     TEXT NOT NULL,
  created_by    UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  title         TEXT NOT NULL,
  description   TEXT NOT NULL,
  subject       TEXT NOT NULL,
  professor     TEXT NOT NULL,
  due_date      BIGINT NOT NULL,
  type          TEXT DEFAULT 'trabajo',
  created_at    BIGINT NOT NULL,
  tag           TEXT,
  user_id       TEXT NOT NULL DEFAULT '',
  user_name     TEXT NOT NULL DEFAULT '',
  collaborators TEXT[] DEFAULT '{}'
);

-- ─── TASK_PROGRESS (progreso personal en tareas compartidas) ─
CREATE TABLE IF NOT EXISTS public.task_progress (
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  task_id      UUID NOT NULL,
  is_completed BOOLEAN DEFAULT FALSE,
  is_submitted BOOLEAN DEFAULT FALSE,
  updated_at   BIGINT NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, task_id)
);

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE public.profiles       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.careers        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_careers   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subjects       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tasks          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shared_tasks   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_progress  ENABLE ROW LEVEL SECURITY;

-- profiles: cada usuario solo su fila. Sin política de DELETE a propósito.
CREATE POLICY "profiles_select_own" ON public.profiles
  FOR SELECT TO authenticated USING (auth.uid() = id);

CREATE POLICY "profiles_insert_own" ON public.profiles
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- careers: lectura abierta (la pantalla de selección corre antes del login),
-- escritura solo para administradores. NO usar USING (true) para escritura:
-- la anon key viaja en cada APK, así que eso deja borrar todas las carreras
-- a cualquiera.
CREATE POLICY "careers_read" ON public.careers
  FOR SELECT TO anon, authenticated USING (true);

CREATE POLICY "careers_admin_write" ON public.careers
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- user_careers: el usuario lee y abandona sus membresías, pero NO se puede
-- insertar solo. Crear una membresía pasa por join_career() (definido en
-- supabase_hardening_2.sql), que es quien valida la clave de acceso. Si el
-- cliente pudiera insertar, la clave de carrera no serviría de nada.
CREATE POLICY "user_careers_select_own" ON public.user_careers
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

CREATE POLICY "user_careers_delete_own" ON public.user_careers
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

-- subjects: lectura según SubjectVisibility (0 soloYo, 1 cursoCompleto,
-- 2 seleccionar); escritura y borrado siempre solo del dueño.
CREATE POLICY "subjects_read_visible" ON public.subjects
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR visibility = 1
    OR (visibility = 2 AND auth.uid()::text = ANY(allowed_users))
  );

CREATE POLICY "subjects_write_own" ON public.subjects
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- tasks: solo el dueño
CREATE POLICY "tasks_own" ON public.tasks
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- shared_tasks: creadores y miembros de la carrera pueden leer y escribir
CREATE POLICY "shared_tasks_member" ON public.shared_tasks
  FOR ALL USING (
    created_by = auth.uid()
    OR
    EXISTS (
      SELECT 1 FROM public.user_careers uc
      WHERE uc.user_id = auth.uid() AND uc.career_id = shared_tasks.career_id
    )
  )
  WITH CHECK (
    created_by = auth.uid()
    OR
    EXISTS (
      SELECT 1 FROM public.user_careers uc
      WHERE uc.user_id = auth.uid() AND uc.career_id = shared_tasks.career_id
    )
  );

-- task_progress: cada usuario gestiona su propio progreso
CREATE POLICY "task_progress_own" ON public.task_progress
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ============================================================
-- TABLA: meetings (Reuniones académicas Zoom, Meet, Teams, etc.)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.meetings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    description TEXT DEFAULT '',
    subject TEXT NOT NULL,
    professor TEXT NOT NULL,
    meeting_date TIMESTAMPTZ NOT NULL,
    type TEXT NOT NULL DEFAULT 'Zoom',
    is_recurrent BOOLEAN NOT NULL DEFAULT FALSE,
    meeting_link TEXT DEFAULT '',
    career_id TEXT,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    is_completed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.meetings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "meetings_own" ON public.meetings
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ============================================================
-- TABLA: active_sessions (Control de 4 sesiones simultáneas Netflix-style)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.active_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    device_name TEXT NOT NULL,
    device_id TEXT NOT NULL,
    last_active TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.active_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "active_sessions_own" ON public.active_sessions
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- ============================================================
-- TABLA: study_files (Metadatos de archivos personales de estudio)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.study_files (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    subject TEXT NOT NULL,
    drive_file_id TEXT NOT NULL,
    mime_type TEXT NOT NULL,
    size_bytes BIGINT NOT NULL,
    drive_link TEXT DEFAULT '',
    user_id TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.study_files ENABLE ROW LEVEL SECURITY;

-- Archivos personales: solo el dueño. Ojo, user_id acá es TEXT, no UUID.
CREATE POLICY "study_files_own" ON public.study_files
  FOR ALL TO authenticated
  USING (user_id = auth.uid()::text)
  WITH CHECK (user_id = auth.uid()::text);

-- ============================================================
-- ÍNDICES B-TREE DE SEGURIDAD Y RENDIMIENTO (Evita Table Scan DoS)
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_tasks_user_id ON public.tasks(user_id);
CREATE INDEX IF NOT EXISTS idx_shared_tasks_career_id ON public.shared_tasks(career_id);
CREATE INDEX IF NOT EXISTS idx_shared_tasks_created_by ON public.shared_tasks(created_by);
CREATE INDEX IF NOT EXISTS idx_user_careers_user_id ON public.user_careers(user_id);
CREATE INDEX IF NOT EXISTS idx_user_careers_career_id ON public.user_careers(career_id);
CREATE INDEX IF NOT EXISTS idx_task_progress_user_id ON public.task_progress(user_id);
CREATE INDEX IF NOT EXISTS idx_meetings_user_id ON public.meetings(user_id);
CREATE INDEX IF NOT EXISTS idx_active_sessions_user_id ON public.active_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_study_files_user_id ON public.study_files(user_id);

-- ============================================================
-- REALTIME (para streams en Flutter)
-- ============================================================
ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;
ALTER PUBLICATION supabase_realtime ADD TABLE public.shared_tasks;
ALTER PUBLICATION supabase_realtime ADD TABLE public.task_progress;
ALTER PUBLICATION supabase_realtime ADD TABLE public.careers;
ALTER PUBLICATION supabase_realtime ADD TABLE public.meetings;
ALTER PUBLICATION supabase_realtime ADD TABLE public.study_files;


