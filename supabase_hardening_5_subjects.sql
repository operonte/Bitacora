-- ============================================================
-- BITÁCORA — Cierre de public.subjects
--
-- La base tenía una política `subjects_public_all` con USING (true) que no
-- estaba en supabase_schema.sql: se creó por fuera y el archivo versionado
-- quedó desactualizado. Con ella, cualquiera con la anon key leía, editaba y
-- borraba las materias de todos los usuarios.
--
-- La política nueva respeta el enum SubjectVisibility de subject_model.dart:
--   0 = soloYo         → solo el dueño
--   1 = cursoCompleto  → cualquier usuario autenticado puede leerla
--   2 = seleccionar    → solo los uid listados en allowed_users
-- Escribir y borrar siempre queda restringido al dueño, sea cual sea la
-- visibilidad: compartir una materia no es cederla.
--
-- Ejecutar en el SQL Editor. Idempotente.
-- ============================================================

ALTER TABLE public.subjects ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "subjects_public_all"    ON public.subjects;
DROP POLICY IF EXISTS "subjects_own"           ON public.subjects;
DROP POLICY IF EXISTS "subjects_read_visible"  ON public.subjects;
DROP POLICY IF EXISTS "subjects_write_own"     ON public.subjects;

-- Lectura: propias, las abiertas al curso, y aquellas donde el usuario está
-- explícitamente en la lista de permitidos.
CREATE POLICY "subjects_read_visible" ON public.subjects
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR visibility = 1
    OR (visibility = 2 AND auth.uid()::text = ANY(allowed_users))
  );

-- Escritura, edición y borrado: solo el dueño.
CREATE POLICY "subjects_write_own" ON public.subjects
  FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ─── VERIFICACIÓN ────────────────────────────────────────────
-- Debe devolver 0 filas.
SELECT tablename, policyname, cmd
FROM   pg_policies
WHERE  schemaname = 'public' AND qual::text = 'true' AND cmd <> 'SELECT';
