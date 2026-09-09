-- Bitácora — agregar o borrar una foto extra del perfil, de forma atómica.
--
-- addExtraPhoto/removeExtraPhoto en el cliente leían extra_photo_urls,
-- mutaban la lista en Dart y reescribían el arreglo entero — dos llamadas
-- casi simultáneas (dos dispositivos, o un reintento de red pisando el
-- segundo toque) partían de la misma lista y la segunda escritura borraba
-- lo que había agregado la primera. array_append/array_remove en un solo
-- UPDATE lo hace atómico del lado de Postgres, sin ida y vuelta al cliente
-- entre leer y escribir.

BEGIN;

CREATE OR REPLACE FUNCTION public.add_profile_photo(p_url TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  SELECT array_length(extra_photo_urls, 1) INTO v_count
    FROM public.profiles WHERE id = auth.uid();

  IF COALESCE(v_count, 0) >= 4 THEN
    RAISE EXCEPTION 'Ya tenés el máximo de 4 fotos. Borrá una para agregar otra.';
  END IF;

  UPDATE public.profiles
     SET extra_photo_urls = array_append(extra_photo_urls, p_url)
   WHERE id = auth.uid();
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_profile_photo(p_url TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.profiles
     SET extra_photo_urls = array_remove(extra_photo_urls, p_url)
   WHERE id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION public.add_profile_photo(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.remove_profile_photo(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.add_profile_photo(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_profile_photo(TEXT) TO authenticated;

COMMIT;
