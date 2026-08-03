-- ============================================================
-- BITÁCORA — Endurecimiento fase 3 (DIFERIDA)
--
-- NO EJECUTAR TODAVÍA.
--
-- Borra careers.access_key, que es la última copia en texto plano de las
-- claves de carrera. Las versiones de la app anteriores a este cambio leen
-- esa columna con `row['access_key'] as String` y CRASHEAN si no está.
--
-- Ejecutar recién cuando ya no queden instalaciones viejas en uso: publica
-- primero la build con el código nuevo, deja pasar el tiempo de actualización
-- y después corre esto.
--
-- Comprobación previa: career_access_keys debe tener una fila por cada
-- carrera, o los usuarios quedan sin poder entrar a esa carrera.
-- ============================================================

-- Debe devolver 0 filas antes de continuar.
SELECT c.id, c.name
FROM   public.careers c
LEFT   JOIN public.career_access_keys k ON k.career_id = c.id
WHERE  k.career_id IS NULL;

-- Descomentar y ejecutar solo cuando la consulta de arriba dé 0 filas
-- y las apps viejas ya estén fuera de circulación:

-- ALTER TABLE public.careers DROP COLUMN IF EXISTS access_key;
