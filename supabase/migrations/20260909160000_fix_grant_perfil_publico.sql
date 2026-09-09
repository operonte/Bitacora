-- Bitácora — arregla un bug real: guardar el perfil (bio, edad, género,
-- situación sentimental, religión, fotos extra) fallaba siempre con un
-- error de permisos de Postgres.
--
-- La migración 20260909130000_perfil_publico.sql agregó las columnas pero
-- nunca amplió el GRANT UPDATE de la tabla profiles, que venía acotado a
-- (display_name, email, photo_url) desde el schema original. Postgres exige
-- el privilegio de columna aparte de RLS — RLS decía que sí, el GRANT decía
-- que no, y ganaba el GRANT. Encontrado con una auditoría del código, no en
-- uso real: toda la función de editar perfil de esta sesión estaba muerta
-- desde que se escribió.

BEGIN;

GRANT UPDATE (bio, age, gender, relationship_status, religion, extra_photo_urls)
  ON public.profiles TO authenticated;

COMMIT;
