-- Bitácora — limpieza: filas de archivos que ya no existen en Google Drive
--
-- Seis filas de `image_c800e8b6.png`, cada una con un `drive_file_id` distinto
-- (seis subidas reales, a seis carpetas de asignatura distintas). Los archivos
-- fueron eliminados de Google Drive por el usuario, pero sus filas quedaron:
-- la Changes API solo informa de lo que pasa **desde** que se pide el token de
-- cambios, así que un borrado anterior a esa primera pasada no aparece en
-- ningún delta y la tarjeta se queda para siempre.
--
-- El barrido completo que ahora hace el botón de sincronizar cubre este caso a
-- futuro. Esto limpia lo que quedó de antes.
--
-- ⚠️ Borra filas y no se puede deshacer. Solo toca las seis filas listadas por
-- su `drive_file_id` exacto: no hay comodines ni borrado por nombre.

BEGIN;

DELETE FROM public.study_files
 WHERE drive_file_id IN (
   '1ZVlOeEgL3PB2OLCKhdlM0jyBJuu0Zg_Q',  -- Hebreo II
   '1H6V5Ku6QRgnp70VMY2RRGt1HQx9a8eL6',  -- Historia de Israel II
   '1o3OKWRaEHXXJuyNN4Lfob-rZByGDQ_7i',  -- Palestina en tiempos de Jesus
   '18cYSbOtJtM6Dqh2hZJ_lv9eZtYA2Lm6N',  -- Contexto literario del N.T
   '1owh05WI-oSK1Ywv3gmHI4EvbMNVHsAkE',  -- Historia de iglesia II
   '1x38VJSi8C-hdlX5dBKi5-uKrDfEpDlRe'   -- Introducción a la Teología Práctica
 );

COMMIT;

-- Verificación: no debe devolver ninguna fila.
--
-- SELECT id, name, subject FROM public.study_files
--  WHERE name = 'image_c800e8b6.png';
