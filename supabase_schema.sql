-- ============================================================
-- BITÁCORA — Esquema PostgreSQL para Supabase
-- Pegar en: supabase.com/dashboard/project/pigrmmxmcmtdppkhnsbw/sql/new
-- ============================================================

-- ─── PROFILES (extensión de auth.users) ─────────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
  id                  UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name        TEXT,
  email               TEXT,
  photo_url           TEXT,
  admin_password_hash TEXT,
  created_at          TIMESTAMPTZ DEFAULT NOW()
);

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
  access_key          TEXT NOT NULL,
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

-- profiles
CREATE POLICY "profiles_own" ON public.profiles
  FOR ALL USING (auth.uid() = id);

-- careers: lectura y modificación pública/autenticada
DROP POLICY IF EXISTS "careers_read" ON public.careers;
DROP POLICY IF EXISTS "careers_all" ON public.careers;
CREATE POLICY "careers_public_all" ON public.careers
  FOR ALL USING (true)
  WITH CHECK (true);

-- user_careers: cada usuario gestiona sus membresías
CREATE POLICY "user_careers_own" ON public.user_careers
  FOR ALL USING (auth.uid() = user_id);

-- subjects: solo el dueño
CREATE POLICY "subjects_own" ON public.subjects
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

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

CREATE POLICY "study_files_public_all" ON public.study_files
  FOR ALL USING (true) WITH CHECK (true);

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


