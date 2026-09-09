-- Bitácora — comentarios públicos en el perfil, la alternativa segura al
-- chat privado que se pidió y se descartó: visibles para toda la carrera
-- (nada oculto entre dos personas), y el dueño del perfil puede borrar lo
-- que le dejen, igual que en cualquier red social con moderación básica.
--
-- RLS directa (no RPC): el patrón ya usado en announcements — visible para
-- quien comparte carrera, insertable por quien comparte carrera, borrable
-- por el autor o por el dueño del perfil.

BEGIN;

CREATE TABLE public.profile_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_by UUID NOT NULL,
  created_by_name TEXT,
  text TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_profile_comments_profile
  ON public.profile_comments(profile_user_id, created_at DESC);

ALTER TABLE public.profile_comments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profile_comments_select" ON public.profile_comments
  FOR SELECT TO authenticated USING (
    EXISTS (
      SELECT 1
        FROM public.user_careers mine
        JOIN public.user_careers theirs ON theirs.career_id = mine.career_id
       WHERE mine.user_id = auth.uid()
         AND theirs.user_id = profile_comments.profile_user_id
    )
  );

CREATE POLICY "profile_comments_insert" ON public.profile_comments
  FOR INSERT TO authenticated WITH CHECK (
    created_by = auth.uid()
    AND EXISTS (
      SELECT 1
        FROM public.user_careers mine
        JOIN public.user_careers theirs ON theirs.career_id = mine.career_id
       WHERE mine.user_id = auth.uid()
         AND theirs.user_id = profile_comments.profile_user_id
    )
  );

CREATE POLICY "profile_comments_delete" ON public.profile_comments
  FOR DELETE TO authenticated USING (
    created_by = auth.uid() OR profile_user_id = auth.uid()
  );

COMMIT;
