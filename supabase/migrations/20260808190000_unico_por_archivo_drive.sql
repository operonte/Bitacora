-- Bitácora — endurecimiento 19: un archivo de Drive, una sola fila
--
-- El mismo archivo de Drive llegó a estar registrado dos veces para el mismo
-- usuario. Lo provocaba el escaneo de Drive del cliente, que construía cada
-- StudyFile sin id y dejaba que `saveFile()` le asignara uno nuevo; su única
-- defensa era comparar contra la caché local, que a veces estaba vacía.
--
-- Ese escaneo ya no existe en el código, pero sí en las versiones de la app
-- que la gente tenga instaladas, y siguen escribiendo. Una regla del cliente
-- no protege de un cliente viejo: esto lo cierra en la base.
--
-- Índice parcial: `drive_file_id` es NULL en los enlaces externos, y en un
-- índice único los NULL no chocan entre sí, así que se pueden guardar todos
-- los enlaces que se quiera.

BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS study_files_unico_por_drive_file
  ON public.study_files (user_id, drive_file_id)
  WHERE drive_file_id IS NOT NULL AND btrim(drive_file_id) <> '';

COMMIT;

-- Verificación: debe fallar con "duplicate key value".
--
-- INSERT INTO public.study_files (id, name, subject, drive_file_id, drive_link, user_id, career_id)
-- SELECT 'prueba', name, subject, drive_file_id, drive_link, user_id, career_id
--   FROM public.study_files WHERE drive_file_id IS NOT NULL LIMIT 1;
