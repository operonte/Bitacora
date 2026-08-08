-- ============================================================
-- BITÁCORA — Limpieza de restos del endurecimiento
--
-- Dos cosas que quedaron vivas sin usarse:
--
-- 1. careers.access_key — obsoleta desde la migración 2, cuando las claves
--    pasaron a career_access_keys hasheadas. Se dejó por compatibilidad con
--    las apps ya instaladas; a estas alturas ninguna versión soportada la
--    lee ni la escribe.
--
-- 2. active_sessions — tabla del límite de 4 dispositivos simultáneos. El
--    servicio que la usaba (SessionControlService) nunca se llamó desde
--    ninguna pantalla y se borró del código en esta misma tanda.
--
--    COMPROBADO contra producción con `supabase db dump`: esta tabla NUNCA
--    llegó a crearse. Estaba en supabase_schema.sql pero no en la base. El
--    DROP de abajo es un no-op y se deja solo por si alguna instalación sí
--    la tiene.
--
-- ATENCIÓN:
--   - Si alguna instalación muy antigua todavía leyera careers.access_key,
--     dejaría de funcionar. Como la columna quedó siempre en '' desde la
--     migración 2, esas versiones ya estaban rotas igual.
--
-- Ejecutar en el SQL Editor. Idempotente.
-- ============================================================

-- ─── 1. Columna obsoleta ─────────────────────────────────────
ALTER TABLE public.careers
  DROP COLUMN IF EXISTS access_key;

-- ─── 2. Tabla sin uso ────────────────────────────────────────
-- Sale primero de la publicación de realtime; si no, DROP TABLE falla
-- mientras siga listada ahí.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'active_sessions'
  ) THEN
    ALTER PUBLICATION supabase_realtime DROP TABLE public.active_sessions;
  END IF;
END $$;

DROP TABLE IF EXISTS public.active_sessions;

-- ─── VERIFICACIÓN ────────────────────────────────────────────
-- Espera cero filas en las dos consultas.
SELECT column_name
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  table_name  = 'careers'
  AND  column_name = 'access_key';

SELECT table_name
FROM   information_schema.tables
WHERE  table_schema = 'public'
  AND  table_name  = 'active_sessions';
