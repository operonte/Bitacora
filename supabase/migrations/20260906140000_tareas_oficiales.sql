-- Bitácora — Fase 2 del ecosistema docente: tareas oficiales.
--
-- Hoy shared_tasks_member es FOR ALL: cualquier miembro de la carrera puede
-- editar o borrar la tarea de cualquier otro. Sirve para tareas armadas
-- entre compañeros, pero una tarea de un docente no debería poder borrarla
-- un alumno sin querer.
--
-- Se agrega is_official (por defecto FALSE, no cambia nada de lo que ya
-- existe) y se separa la política por comando: SELECT/INSERT siguen iguales,
-- UPDATE/DELETE solo los puede tocar quien la creó una vez que es oficial.
-- Poner is_official = TRUE, al crear o al editar, exige ser docente de esa
-- carrera — si no, cualquiera podría marcar su propia tarea como oficial.

BEGIN;

ALTER TABLE public.shared_tasks
  ADD COLUMN IF NOT EXISTS is_official BOOLEAN NOT NULL DEFAULT FALSE;

DROP POLICY IF EXISTS "shared_tasks_member" ON public.shared_tasks;

CREATE POLICY "shared_tasks_select" ON public.shared_tasks
  FOR SELECT USING (
    created_by = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.user_careers uc
      WHERE uc.user_id = auth.uid() AND uc.career_id = shared_tasks.career_id
    )
  );

CREATE POLICY "shared_tasks_insert" ON public.shared_tasks
  FOR INSERT WITH CHECK (
    (
      created_by = auth.uid()
      OR EXISTS (
        SELECT 1 FROM public.user_careers uc
        WHERE uc.user_id = auth.uid() AND uc.career_id = shared_tasks.career_id
      )
    )
    AND (
      NOT is_official
      OR EXISTS (
        SELECT 1 FROM public.user_careers uc
        WHERE uc.user_id = auth.uid() AND uc.career_id = shared_tasks.career_id
          AND uc.role = 'docente'
      )
    )
  );

-- UPDATE/DELETE: una tarea normal (is_official = FALSE) la sigue pudiendo
-- tocar cualquier miembro, como hasta ahora. Una oficial, solo quien la creó.
CREATE POLICY "shared_tasks_update" ON public.shared_tasks
  FOR UPDATE USING (
    created_by = auth.uid()
    OR (
      NOT is_official
      AND EXISTS (
        SELECT 1 FROM public.user_careers uc
        WHERE uc.user_id = auth.uid() AND uc.career_id = shared_tasks.career_id
      )
    )
  )
  WITH CHECK (
    (
      created_by = auth.uid()
      OR (
        NOT is_official
        AND EXISTS (
          SELECT 1 FROM public.user_careers uc
          WHERE uc.user_id = auth.uid() AND uc.career_id = shared_tasks.career_id
        )
      )
    )
    AND (
      NOT is_official
      OR EXISTS (
        SELECT 1 FROM public.user_careers uc
        WHERE uc.user_id = auth.uid() AND uc.career_id = shared_tasks.career_id
          AND uc.role = 'docente'
      )
    )
  );

CREATE POLICY "shared_tasks_delete" ON public.shared_tasks
  FOR DELETE USING (
    created_by = auth.uid()
    OR (
      NOT is_official
      AND EXISTS (
        SELECT 1 FROM public.user_careers uc
        WHERE uc.user_id = auth.uid() AND uc.career_id = shared_tasks.career_id
      )
    )
  );

COMMIT;
