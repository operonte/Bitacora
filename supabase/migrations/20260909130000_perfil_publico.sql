-- Bitácora — perfil expandido y público dentro de la carrera.
--
-- profiles ya existía (nombre, email, foto, is_admin) con RLS restringida a
-- la propia fila (profiles_select_own): nadie podía leer el perfil de otro
-- directamente. Se agregan campos personales opcionales (bio, edad, género,
-- situación sentimental, religión, un par de fotos extra) y un RPC
-- SECURITY DEFINER para verlos — mismo patrón que get_student_risk o
-- get_task_submission_status, no una política RLS nueva y amplia.
--
-- El límite de "público" es la carrera compartida, igual que anuncios,
-- tareas oficiales y material docente: nunca toda la instalación.

BEGIN;

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS bio TEXT,
  ADD COLUMN IF NOT EXISTS age INT,
  ADD COLUMN IF NOT EXISTS gender TEXT,
  ADD COLUMN IF NOT EXISTS relationship_status TEXT,
  ADD COLUMN IF NOT EXISTS religion TEXT,
  ADD COLUMN IF NOT EXISTS extra_photo_urls TEXT[] NOT NULL DEFAULT '{}';

CREATE OR REPLACE FUNCTION public.get_public_profile(p_user_id UUID)
RETURNS TABLE (
  user_id UUID,
  display_name TEXT,
  photo_url TEXT,
  extra_photo_urls TEXT[],
  bio TEXT,
  age INT,
  gender TEXT,
  relationship_status TEXT,
  religion TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

  RETURN QUERY
    SELECT p.id, p.display_name, p.photo_url, p.extra_photo_urls,
           p.bio, p.age, p.gender, p.relationship_status, p.religion
      FROM public.profiles p
     WHERE p.id = p_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_public_profile(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_public_profile(UUID) TO authenticated;

COMMIT;
