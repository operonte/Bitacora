-- Historias de perfil (como WhatsApp): foto o video corto, visibles 48 h y
-- después se borran. Una sola historia activa por persona — subir una nueva
-- reemplaza la anterior (el cliente borra la fila vieja y revoca su link de
-- Drive antes de insertar la nueva).
CREATE TABLE public.stories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  media_url text NOT NULL,
  media_type text NOT NULL CHECK (media_type IN ('photo', 'video')),
  drive_file_id text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX stories_user_id_idx ON public.stories(user_id);

ALTER TABLE public.stories ENABLE ROW LEVEL SECURITY;

-- Sin política de SELECT a propósito: la única lectura permitida es a
-- través de get_active_story, que además hace la limpieza de las vencidas
-- (no hay cron en este proyecto) y el chequeo de "compartís una carrera".
CREATE POLICY stories_insert ON public.stories
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY stories_delete ON public.stories
  FOR DELETE USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.get_active_story(p_user_id uuid)
RETURNS TABLE(id uuid, media_url text, media_type text, drive_file_id text, created_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF p_user_id <> auth.uid() AND NOT EXISTS (
    SELECT 1
      FROM public.user_careers mine
      JOIN public.user_careers theirs
        ON theirs.career_id = mine.career_id
     WHERE mine.user_id = auth.uid()
       AND theirs.user_id = p_user_id
  ) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  -- Limpieza perezosa: sin cron, se borra lo vencido de esta persona cada
  -- vez que alguien (incluida ella misma) la consulta.
  DELETE FROM public.stories s
   WHERE s.user_id = p_user_id AND s.created_at < now() - interval '48 hours';

  RETURN QUERY
    SELECT s.id, s.media_url, s.media_type, s.drive_file_id, s.created_at
      FROM public.stories s
     WHERE s.user_id = p_user_id
     ORDER BY s.created_at DESC
     LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_active_story(uuid) TO authenticated;
