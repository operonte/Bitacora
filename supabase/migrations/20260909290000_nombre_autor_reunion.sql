-- Bitácora — reuniones compartidas no decían quién las había cargado. El
-- comentario del propio código ya lo reconocía ("una reunión compartida por
-- otro miembro se ve pero no se toca") pero nunca mostraba a quién
-- pertenecía — a diferencia de anuncios, que sí resuelven y muestran el
-- nombre del autor. Mismo patrón que ya usan tasks/announcements: el
-- nombre lo estampa el cliente al crear, columna de texto plano, no un
-- join en vivo contra profiles.
--
-- Se completa (best effort, con el nombre de HOY, no el de cuando se creó)
-- para las reuniones ya existentes, para no dejar el dato vacío en todo lo
-- viejo.

BEGIN;

ALTER TABLE public.meetings
  ADD COLUMN IF NOT EXISTS user_name TEXT;

UPDATE public.meetings m
   SET user_name = COALESCE(NULLIF(p.display_name, ''), p.email)
  FROM public.profiles p
 WHERE p.id = m.user_id
   AND m.user_name IS NULL;

COMMIT;
