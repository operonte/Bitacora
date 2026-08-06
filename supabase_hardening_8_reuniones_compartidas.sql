-- ============================================================
-- BITÁCORA — Reuniones privadas o compartidas con la carrera
--
-- Hasta ahora career_id se guardaba en meetings pero era solo una etiqueta
-- para el filtro local: la política meetings_own (auth.uid() = user_id) y la
-- consulta del cliente (.eq('user_id', ...)) hacían que NADIE más pudiera
-- ver una reunión, tuviera carrera o no.
--
-- Ahora quien crea la reunión elige: privada (solo él) o compartida con los
-- miembros de esa carrera. Se resuelve con una columna is_private en la
-- tabla que ya existe, en vez de duplicar la tabla como se hizo con
-- shared_tasks — las reuniones no tienen colaboradores ni progreso por
-- usuario, así que no justifican esa complejidad.
--
-- IMPORTANTE: is_private arranca en TRUE para que las reuniones ya creadas
-- no se vuelvan visibles para nadie de golpe. Compartir es una acción
-- explícita del usuario.
--
-- Ejecutar en el SQL Editor. Idempotente.
-- ============================================================

ALTER TABLE public.meetings
  ADD COLUMN IF NOT EXISTS is_private BOOLEAN NOT NULL DEFAULT TRUE;

-- Una reunión compartida sin carrera no tendría con quién compartirse: sería
-- invisible para todos menos su dueño, que es justo lo que is_private ya
-- expresa. Se fuerza la coherencia en la base y no solo en la UI.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'meetings_shared_needs_career_chk'
  ) THEN
    ALTER TABLE public.meetings
      ADD CONSTRAINT meetings_shared_needs_career_chk
      CHECK (is_private OR (career_id IS NOT NULL AND career_id <> ''));
  END IF;
END $$;

-- ─── RLS ─────────────────────────────────────────────────────
-- Reemplaza meetings_own por una política que además deja leer las
-- reuniones compartidas de las carreras a las que el usuario pertenece.
-- Se separa por operación: cualquier miembro LEE las compartidas, pero solo
-- el dueño puede modificarlas o borrarlas.
DROP POLICY IF EXISTS "meetings_own" ON public.meetings;
-- Creada a mano en el dashboard, nunca estuvo en el repo. Es FOR ALL con
-- auth.uid() = user_id: un subconjunto de lo que ya conceden las políticas
-- de abajo, así que no expone nada, pero duplica reglas y confunde.
DROP POLICY IF EXISTS "permitir_gestion_reuniones" ON public.meetings;
DROP POLICY IF EXISTS "meetings_select" ON public.meetings;
DROP POLICY IF EXISTS "meetings_insert" ON public.meetings;
DROP POLICY IF EXISTS "meetings_update" ON public.meetings;
DROP POLICY IF EXISTS "meetings_delete" ON public.meetings;

CREATE POLICY "meetings_select" ON public.meetings
  FOR SELECT USING (
    auth.uid() = user_id
    OR (
      is_private = FALSE
      AND EXISTS (
        SELECT 1 FROM public.user_careers uc
        WHERE uc.user_id = auth.uid() AND uc.career_id = meetings.career_id
      )
    )
  );

-- Escritura: solo el dueño. Un miembro que ve una reunión compartida no
-- puede editarla ni borrarla — si pudiera, cualquiera del grupo borraría las
-- reuniones de los demás.
CREATE POLICY "meetings_insert" ON public.meetings
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "meetings_update" ON public.meetings
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "meetings_delete" ON public.meetings
  FOR DELETE USING (auth.uid() = user_id);

-- Acelera el SELECT de arriba, que filtra por carrera + visibilidad.
CREATE INDEX IF NOT EXISTS idx_meetings_career_shared
  ON public.meetings(career_id) WHERE is_private = FALSE;

-- ─── VERIFICACIÓN ────────────────────────────────────────────
SELECT column_name, data_type, is_nullable, column_default
FROM   information_schema.columns
WHERE  table_schema = 'public' AND table_name = 'meetings'
ORDER  BY ordinal_position;

SELECT policyname, cmd, qual
FROM   pg_policies
WHERE  schemaname = 'public' AND tablename = 'meetings'
ORDER  BY policyname;
