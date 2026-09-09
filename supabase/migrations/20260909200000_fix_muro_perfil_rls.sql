-- Bitácora — arregla bug real: no se podía escribir (ni leer) en el muro de
-- otra persona.
--
-- profile_comments_select/_insert comparaban filas de user_careers de DOS
-- usuarios distintos ("mine" y "theirs") dentro de una política RLS común
-- (no SECURITY DEFINER). user_careers_select_own restringe user_careers a
-- "auth.uid() = user_id", así que "theirs" (la fila del OTRO usuario) es
-- invisible bajo RLS para cualquiera que no sea el propio dueño del perfil:
-- el EXISTS daba falso incluso compartiendo carrera de verdad. Por eso
-- comentar en el propio muro funcionaba (mine = theirs = la fila propia) y
-- en el de cualquier otra persona, no — el caso reportado.
--
-- Arreglo: un helper SECURITY DEFINER (mismo patrón que is_docente) que sí
-- puede leer ambas filas para responder "¿comparte carrera conmigo?", sin
-- abrir user_careers en sí.

BEGIN;

CREATE OR REPLACE FUNCTION public.shares_career_with(p_other_user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.user_careers mine
      JOIN public.user_careers theirs ON theirs.career_id = mine.career_id
     WHERE mine.user_id = auth.uid()
       AND theirs.user_id = p_other_user_id
  );
$$;

REVOKE ALL ON FUNCTION public.shares_career_with(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.shares_career_with(UUID) TO authenticated;

DROP POLICY IF EXISTS "profile_comments_select" ON public.profile_comments;
CREATE POLICY "profile_comments_select" ON public.profile_comments
  FOR SELECT TO authenticated USING (
    public.shares_career_with(profile_comments.profile_user_id)
  );

DROP POLICY IF EXISTS "profile_comments_insert" ON public.profile_comments;
CREATE POLICY "profile_comments_insert" ON public.profile_comments
  FOR INSERT TO authenticated WITH CHECK (
    created_by = auth.uid()
    AND public.shares_career_with(profile_comments.profile_user_id)
  );

COMMIT;
