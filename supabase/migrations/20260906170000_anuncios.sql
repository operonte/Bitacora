-- Bitácora — Fase 4 del ecosistema docente: anuncios por asignatura.
--
-- A diferencia de asistencia, esto sí necesita Realtime (la lista se
-- actualiza sola mientras la pantalla está abierta), así que la política es
-- RLS directa sobre la tabla, igual que shared_tasks y meetings — no un RPC
-- cerrado: Realtime evalúa la política de SELECT de cada cliente conectado,
-- no pasa por RPCs.
--
-- Solo un docente de la carrera puede crear uno; cualquier miembro lo lee.
-- Editar o borrar, solo quien lo creó.

BEGIN;

CREATE TABLE IF NOT EXISTS public.announcements (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  career_id        TEXT NOT NULL REFERENCES public.careers(id) ON DELETE CASCADE,
  -- Null = para toda la carrera. Con valor, se filtra por esa asignatura.
  subject          TEXT,
  title            TEXT NOT NULL,
  body             TEXT NOT NULL DEFAULT '',
  urgent           BOOLEAN NOT NULL DEFAULT FALSE,
  created_by       UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_by_name  TEXT NOT NULL DEFAULT '',
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.announcements ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_announcements_career ON public.announcements(career_id);

CREATE POLICY "announcements_select" ON public.announcements
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.user_careers uc
      WHERE uc.user_id = auth.uid() AND uc.career_id = announcements.career_id
    )
  );

CREATE POLICY "announcements_insert" ON public.announcements
  FOR INSERT WITH CHECK (
    created_by = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.user_careers uc
      WHERE uc.user_id = auth.uid() AND uc.career_id = announcements.career_id
        AND uc.role = 'docente'
    )
  );

CREATE POLICY "announcements_update" ON public.announcements
  FOR UPDATE USING (created_by = auth.uid()) WITH CHECK (created_by = auth.uid());

CREATE POLICY "announcements_delete" ON public.announcements
  FOR DELETE USING (created_by = auth.uid());

ALTER PUBLICATION supabase_realtime ADD TABLE public.announcements;

COMMIT;
