-- Posición vertical de la foto de portada (como Facebook: no recorta el
-- archivo, solo recuerda qué parte mostrar dentro del marco). -1 = arriba
-- del todo, 0 = centro (default), 1 = abajo del todo — mismo rango que
-- Alignment en Flutter, para no tener que convertir nada del lado cliente.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS cover_photo_offset double precision NOT NULL DEFAULT 0;

-- Lección de la migración anterior (fix_grant_columnas_nuevas_perfil):
-- profiles usa permisos por columna, no por tabla — sin este GRANT explícito
-- quedaría "permission denied" igual que pasó con cover_photo_url.
GRANT UPDATE (cover_photo_offset) ON public.profiles TO authenticated;

DROP FUNCTION IF EXISTS public.get_public_profile(uuid);

CREATE FUNCTION public.get_public_profile(p_user_id uuid)
 RETURNS TABLE(user_id uuid, display_name text, photo_url text, extra_photo_urls text[], bio text, age integer, gender text, relationship_status text, religion text, phone text, social_media text, interests text, previous_career text, occupation text, email text, cover_photo_url text, cover_photo_offset double precision)
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
           p.phone, p.social_media, p.interests, p.previous_career, p.occupation,
           p.email, p.cover_photo_url, p.cover_photo_offset
      FROM public.profiles p
     WHERE p.id = p_user_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_public_profile(uuid) TO anon, authenticated, service_role;
