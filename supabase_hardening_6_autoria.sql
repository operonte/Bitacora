-- ============================================================
-- BITÁCORA — La autoría de creación es inmutable
--
-- Al editar una tarea compartida, el cliente mandaba user_name en el UPDATE,
-- así que el nombre del creador quedaba reemplazado por el del editor: una
-- tarea creada por A y editada por B mostraba "creada por B, editada por B".
--
-- El cliente ya no manda esos campos, pero eso solo arregla a los clientes
-- actualizados. Acá el trigger los preserva por su cuenta, de modo que
-- ninguna versión de la app —vieja, modificada, o alguien pegándole directo
-- a la API con la anon key— pueda reescribir quién creó una tarea.
--
-- Ejecutar en el SQL Editor. Idempotente.
-- ============================================================

CREATE OR REPLACE FUNCTION public.stamp_shared_task_author()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name TEXT;
BEGIN
  SELECT COALESCE(NULLIF(TRIM(p.display_name), ''), NULLIF(TRIM(p.email), ''))
    INTO v_name
  FROM public.profiles p
  WHERE p.id = auth.uid();

  IF v_name IS NULL THEN
    SELECT NULLIF(TRIM(u.email), '') INTO v_name
    FROM auth.users u WHERE u.id = auth.uid();
  END IF;

  v_name := COALESCE(v_name, 'Usuario');

  IF TG_OP = 'INSERT' THEN
    NEW.created_by      := auth.uid();
    NEW.created_by_name := v_name;
    NEW.user_id         := COALESCE(NULLIF(NEW.user_id, ''), auth.uid()::text);
    NEW.user_name       := COALESCE(NULLIF(TRIM(NEW.user_name), ''), v_name);
    NEW.updated_by      := NULL;
    NEW.updated_by_name := NULL;
    NEW.updated_at      := NULL;
  ELSE
    -- Autoría de creación: intocable en un UPDATE, venga lo que venga del
    -- cliente. user_id y user_name identifican al creador, no al editor.
    NEW.created_by      := OLD.created_by;
    NEW.created_by_name := OLD.created_by_name;
    NEW.user_id         := OLD.user_id;
    NEW.user_name       := OLD.user_name;
    NEW.career_id       := OLD.career_id;

    NEW.updated_by      := auth.uid();
    NEW.updated_by_name := v_name;
    NEW.updated_at      := NOW();
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS shared_tasks_stamp_author ON public.shared_tasks;
CREATE TRIGGER shared_tasks_stamp_author
  BEFORE INSERT OR UPDATE ON public.shared_tasks
  FOR EACH ROW EXECUTE FUNCTION public.stamp_shared_task_author();

-- ─── DIAGNÓSTICO ─────────────────────────────────────────────
-- Correr y mandar los tres resultados.

-- (1) Estado de autoría de las tareas compartidas recientes.
SELECT id, title, career_id,
       user_id, user_name,
       created_by, created_by_name,
       updated_by, updated_by_name, updated_at
FROM   public.shared_tasks
ORDER  BY created_at DESC
LIMIT  10;

-- (2) Quién es miembro de qué carrera. Si un usuario no aparece acá, solo ve
--     las tareas compartidas que él mismo creó.
SELECT uc.career_id, u.email, uc.joined_at
FROM   public.user_careers uc
JOIN   auth.users u ON u.id = uc.user_id
ORDER  BY uc.career_id, u.email;

-- (3) Políticas reales de shared_tasks.
SELECT policyname, cmd, qual::text AS using_expr, with_check::text AS check_expr
FROM   pg_policies
WHERE  schemaname = 'public' AND tablename = 'shared_tasks';
