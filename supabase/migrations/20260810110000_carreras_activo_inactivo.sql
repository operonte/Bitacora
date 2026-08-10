-- Bitácora — desactivar carreras en vez de borrarlas
--
-- Borrar una carrera con tareas/reuniones/archivos asociados los dejaba
-- huérfanos e imposibles de editar (el trigger de carrera-y-asignatura
-- obligatorias exige que career_id exista). La solución no es "permitir el
-- borrado igual": es no borrar. Se agrega una alternativa real:
--
--   · careers.is_active: si es falsa, la carrera sigue existiendo con todo su
--     contenido intacto y visible, pero no admite tareas, reuniones ni
--     archivos NUEVOS (ni join_career deja inscribirse). Lo que ya existía
--     no se toca — el trigger de abajo solo corre en INSERT y en UPDATE
--     cuando career_id o subject cambian, igual que el resto de esta validación.
--   · El borrado real (DELETE) ahora se bloquea si queda algo asociado. Sigue
--     sirviendo para carreras creadas por error, sin contenido.
--
-- Las materias predefinidas no necesitan un flag propio: viven en
-- careers.predefined_subjects (JSON) y sacarlas de ahí con
-- removeSubjectFromCareer ya logra exactamente esto (no se puede volver a
-- elegir, lo ya guardado no cambia) — es el mecanismo que ya existía.

BEGIN;

ALTER TABLE public.careers
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT true;

-- ─── 1. BLOQUEA EL BORRADO SI QUEDA ALGO ASOCIADO ────────────
-- admin_career_impact() ya le muestra esto al admin antes de confirmar; este
-- trigger es la versión que no se puede saltar aunque el borrado se dispare
-- por otro camino que no sea la app.

CREATE OR REPLACE FUNCTION public.prevent_career_delete_with_data()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count BIGINT;
BEGIN
  SELECT
    (SELECT count(*) FROM public.tasks        WHERE career_id = OLD.id) +
    (SELECT count(*) FROM public.shared_tasks WHERE career_id = OLD.id) +
    (SELECT count(*) FROM public.meetings     WHERE career_id = OLD.id) +
    (SELECT count(*) FROM public.study_files  WHERE career_id = OLD.id)
  INTO v_count;

  IF v_count > 0 THEN
    RAISE EXCEPTION
      'No se puede eliminar "%": tiene % filas asociadas (tareas, reuniones o archivos). Desactívala en vez de borrarla.',
      OLD.name, v_count;
  END IF;

  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS careers_block_delete_with_data ON public.careers;
CREATE TRIGGER careers_block_delete_with_data
  BEFORE DELETE ON public.careers
  FOR EACH ROW EXECUTE FUNCTION public.prevent_career_delete_with_data();

-- ─── 2. UNA CARRERA INACTIVA NO ADMITE CONTENIDO NUEVO ───────
-- Mismo trigger de siempre (assert_subject_belongs_to_career), con un chequeo
-- más antes de la asignatura.

CREATE OR REPLACE FUNCTION public.assert_subject_belongs_to_career()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_career_name   TEXT;
  v_career_active BOOLEAN;
  v_ok            BOOLEAN;
BEGIN
  IF NEW.career_id IS NULL OR btrim(NEW.career_id) = '' THEN
    RAISE EXCEPTION 'Falta la carrera: no se puede guardar sin ella';
  END IF;

  IF NEW.subject IS NULL OR btrim(NEW.subject) = '' THEN
    RAISE EXCEPTION 'Falta la asignatura: no se puede guardar sin ella';
  END IF;

  SELECT c.name, c.is_active INTO v_career_name, v_career_active
    FROM public.careers c WHERE c.id = NEW.career_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'La carrera % no existe', NEW.career_id;
  END IF;

  IF NOT v_career_active THEN
    RAISE EXCEPTION
      'La carrera "%" está desactivada: no admite contenido nuevo',
      v_career_name;
  END IF;

  SELECT EXISTS (
    -- Materia de la carrera.
    SELECT 1
      FROM public.careers c,
           LATERAL jsonb_array_elements(c.predefined_subjects) AS s
     WHERE c.id = NEW.career_id
       AND lower(btrim(s->>'name')) = lower(btrim(NEW.subject))
    UNION ALL
    -- Materia propia de quien escribe.
    SELECT 1
      FROM public.subjects sub
     WHERE sub.user_id = auth.uid()
       AND lower(btrim(sub.name)) = lower(btrim(NEW.subject))
  ) INTO v_ok;

  IF NOT v_ok THEN
    RAISE EXCEPTION
      'La asignatura "%" no pertenece a la carrera "%"',
      NEW.subject, v_career_name;
  END IF;

  RETURN NEW;
END;
$$;

-- ─── 3. join_career() TAMBIÉN LA RECHAZA ──────────────────────
-- Después de confirmar la clave, no antes: si la clave es correcta pero la
-- carrera está inactiva, el problema no es un intento fallido (no debe sumar
-- al contador de fuerza bruta), es que dejó de aceptar gente nueva.

CREATE OR REPLACE FUNCTION public.join_career(p_access_key TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_career_id TEXT;
  v_key_hash  TEXT;
  v_locked    TIMESTAMPTZ;
  v_active    BOOLEAN;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;

  SELECT locked_until INTO v_locked
    FROM public.career_join_attempts
   WHERE user_id = auth.uid();

  IF v_locked IS NOT NULL AND v_locked > NOW() THEN
    RAISE EXCEPTION 'Demasiados intentos. Probá de nuevo en unos minutos.';
  END IF;

  IF COALESCE(p_access_key, '') = '' THEN
    RETURN NULL;
  END IF;

  SELECT k.career_id, k.key_hash INTO v_career_id, v_key_hash
  FROM   public.career_access_keys k
  WHERE  k.key_hash = CASE
           WHEN k.key_hash LIKE '$2%'
             THEN extensions.crypt(p_access_key, k.key_hash)
           ELSE encode(extensions.digest(p_access_key, 'sha256'), 'hex')
         END
  LIMIT  1;

  IF v_career_id IS NULL THEN
    INSERT INTO public.career_join_attempts (user_id, failed_attempts, locked_until)
    VALUES (auth.uid(), 1, NULL)
    ON CONFLICT (user_id) DO UPDATE
      SET failed_attempts = career_join_attempts.failed_attempts + 1,
          locked_until = CASE
            WHEN career_join_attempts.failed_attempts + 1 >= 5
              THEN NOW() + INTERVAL '15 minutes'
            ELSE career_join_attempts.locked_until
          END,
          updated_at = NOW();
    RETURN NULL;
  END IF;

  DELETE FROM public.career_join_attempts WHERE user_id = auth.uid();

  IF v_key_hash NOT LIKE '$2%' THEN
    UPDATE public.career_access_keys
       SET key_hash   = extensions.crypt(p_access_key, extensions.gen_salt('bf', 10)),
           updated_at = NOW()
     WHERE career_id = v_career_id;
  END IF;

  SELECT is_active INTO v_active FROM public.careers WHERE id = v_career_id;
  IF NOT COALESCE(v_active, true) THEN
    RAISE EXCEPTION 'Esta carrera fue desactivada y ya no acepta nuevos miembros.';
  END IF;

  INSERT INTO public.user_careers (user_id, career_id)
  VALUES (auth.uid(), v_career_id)
  ON CONFLICT (user_id, career_id) DO NOTHING;

  RETURN v_career_id;
END;
$$;

REVOKE ALL     ON FUNCTION public.join_career(TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.join_career(TEXT) TO authenticated;

COMMIT;

-- Verificación:
--
-- (a) Desactivar una carrera y probar un INSERT en study_files/tasks/meetings
--     con ese career_id: debe fallar con "está desactivada".
-- (b) Una carrera con is_active = false y datos asociados: editar un campo
--     que no sea subject/career en una fila existente debe seguir funcionando
--     (el trigger de UPDATE no se dispara si no cambiaron esos dos campos).
-- (c) Borrar una carrera sin filas asociadas debe seguir funcionando igual
--     que antes.
