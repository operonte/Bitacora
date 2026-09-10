-- profiles usa permisos por columna, no por tabla entera (ver
-- fix_grant_perfil_publico de antes en esta misma sesión). Las 6 columnas
-- agregadas hoy (5 de "Información personal" + cover_photo_url) nunca
-- recibieron UPDATE para authenticated — por eso "permission denied for
-- table profiles" al guardar portada o cualquiera de esos campos nuevos.
GRANT UPDATE (phone, social_media, interests, previous_career, occupation, cover_photo_url)
  ON public.profiles TO authenticated;
