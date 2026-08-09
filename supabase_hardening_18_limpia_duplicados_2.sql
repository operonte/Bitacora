-- Bitácora — endurecimiento 18: segunda limpieza de duplicados
--
-- El escaneo de Drive (`syncFromSupabaseAndDrive`, ya eliminado del cliente)
-- construía cada archivo detectado con `StudyFile(...)` **sin id**, y
-- `saveFile()` le asignaba uno nuevo. Su única defensa contra registrar dos
-- veces lo mismo era comparar contra los `drive_file_id` de la caché local:
-- cuando esa caché estaba vacía —navegador recién abierto, o la
-- sincronización previa falló— todos los archivos parecían nuevos y se
-- insertaron otra vez.
--
-- El efecto visible: borrar un archivo desde la app eliminaba el de Drive y su
-- fila, pero la fila gemela seguía mostrando una tarjeta de algo que ya no
-- existe.
--
-- Esto borra las copias y conserva la original de cada archivo: la de id más
-- bajo, que es la primera que se registró.
--
-- ⚠️ Borra filas y no se puede deshacer. Solo toca filas cuyo `drive_file_id`
-- aparece más de una vez para el mismo usuario, o sea copias exactas del mismo
-- archivo de Drive. No hay pérdida real: el archivo sigue en Drive y su
-- registro original se mantiene.

BEGIN;

WITH ranked AS (
  SELECT
    id,
    row_number() OVER (
      PARTITION BY user_id, drive_file_id
      ORDER BY id ASC
    ) AS n
  FROM public.study_files
  WHERE drive_file_id IS NOT NULL
    AND btrim(drive_file_id) <> ''
)
DELETE FROM public.study_files f
 USING ranked r
 WHERE f.id = r.id
   AND r.n > 1;

COMMIT;

-- Verificación: no debe devolver ninguna fila.
--
-- SELECT user_id, drive_file_id, count(*)
--   FROM public.study_files
--  WHERE drive_file_id IS NOT NULL AND btrim(drive_file_id) <> ''
--  GROUP BY 1, 2
-- HAVING count(*) > 1;
