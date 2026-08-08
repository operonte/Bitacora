-- Bitácora — endurecimiento 12: fuera la contraseña maestra de administrador
--
-- Contexto (mejora 2.2 del plan): el acceso al panel de administración se
-- decidía comparando un SHA-256 sin sal contra `_defaultAdminHash`, una
-- constante compilada dentro de cada APK, o contra `profiles.admin_password_hash`.
--
-- Lo primero se extraía del instalador y se rompía fuera de línea; el límite
-- de 5 intentos solo estorbaba dentro de la app. Y cada filtración obligaba a
-- rotar la clave a mano y publicar una versión nueva.
--
-- Desde esta versión la app no consulta ninguna contraseña: pregunta por
-- `public.is_admin()`, que lee `profiles.is_admin` — una columna que el
-- usuario no puede modificar, porque el GRANT de UPDATE sobre `profiles` la
-- deja fuera. Es la misma función que ya usaban las políticas de escritura,
-- así que el permiso real no cambia: cambia solo cómo se decide qué mostrar.
--
-- Este script deja de existir la columna que ya no lee nadie.
--
-- ⚠️ Borra datos y no se puede deshacer. Los hashes que hubiera guardados se
-- pierden, y es justamente el punto.

BEGIN;

-- 1. Quitar la columna del GRANT antes de borrarla. Postgres no lo exige,
--    pero deja el GRANT explícito y legible para quien lo lea después.
REVOKE UPDATE (admin_password_hash) ON public.profiles FROM authenticated;

-- 2. Fuera la columna.
ALTER TABLE public.profiles
  DROP COLUMN IF EXISTS admin_password_hash;

COMMIT;

-- Verificación: no debe devolver ninguna fila.
--
-- SELECT column_name
--   FROM information_schema.columns
--  WHERE table_schema = 'public'
--    AND table_name   = 'profiles'
--    AND column_name  = 'admin_password_hash';
--
-- Y para confirmar quién queda como administrador:
--
-- SELECT id, email, is_admin FROM public.profiles WHERE is_admin;
