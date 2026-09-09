-- Cinco campos opcionales más para "Información personal", pedidos para
-- todas las cuentas (no solo docente): teléfono, redes sociales, intereses,
-- carrera anterior/ocupación y trabajo o profesión — mismo tratamiento que
-- edad/género/situación sentimental/creencias ya existentes: opcionales,
-- visibles para el resto de la carrera.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS phone text,
  ADD COLUMN IF NOT EXISTS social_media text,
  ADD COLUMN IF NOT EXISTS interests text,
  ADD COLUMN IF NOT EXISTS previous_career text,
  ADD COLUMN IF NOT EXISTS occupation text;

-- get_public_profile es RETURNS TABLE con columnas fijas: hay que recrearla
-- (DROP + CREATE, no basta CREATE OR REPLACE) para sumar los 5 campos.
DROP FUNCTION IF EXISTS public.get_public_profile(uuid);

CREATE FUNCTION public.get_public_profile(p_user_id uuid)
 RETURNS TABLE(user_id uuid, display_name text, photo_url text, extra_photo_urls text[], bio text, age integer, gender text, relationship_status text, religion text, phone text, social_media text, interests text, previous_career text, occupation text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
           p.bio, p.age, p.gender, p.relationship_status, p.religion,
           p.phone, p.social_media, p.interests, p.previous_career, p.occupation
      FROM public.profiles p
     WHERE p.id = p_user_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_public_profile(uuid) TO anon, authenticated, service_role;
