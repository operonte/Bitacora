-- Bitácora — Fase 3 del ecosistema docente: asistencia.
--
-- Tabla nueva, sin políticas RLS propias a propósito: RLS queda activada
-- pero vacía, igual que admin_credentials y career_join_attempts — todo el
-- acceso pasa por RPC SECURITY DEFINER que comprueban el rol. Así el cliente
-- nunca puede leer o escribir asistencia ajena aunque se salte la app y
-- llame al API directo.

BEGIN;

CREATE TABLE IF NOT EXISTS public.attendance (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  career_id   TEXT NOT NULL REFERENCES public.careers(id) ON DELETE CASCADE,
  subject     TEXT NOT NULL,
  class_date  DATE NOT NULL,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status      TEXT NOT NULL DEFAULT 'ausente'
                CHECK (status IN ('presente', 'tarde', 'ausente', 'justificado')),
  marked_by   UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  marked_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (career_id, subject, class_date, user_id)
);

ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_attendance_lookup
  ON public.attendance(career_id, subject, class_date);
CREATE INDEX IF NOT EXISTS idx_attendance_user ON public.attendance(user_id);

-- Compartida por las próximas funciones docentes (asistencia, y lo que
-- venga después): evita repetir el mismo EXISTS contra user_careers.role en
-- cada RPC.
CREATE OR REPLACE FUNCTION public.is_docente(p_career_id TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_careers
     WHERE user_id = auth.uid() AND career_id = p_career_id AND role = 'docente'
  );
$$;

-- Roster de la carrera para una clase puntual (asignatura + fecha), con el
-- estado ya marcado o 'sin_marcar' si todavía nadie lo tocó.
CREATE OR REPLACE FUNCTION public.get_attendance_roster(
  p_career_id  TEXT,
  p_subject    TEXT,
  p_class_date DATE
)
RETURNS TABLE (
  user_id      UUID,
  display_name TEXT,
  email        TEXT,
  status       TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_docente(p_career_id) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  RETURN QUERY
    SELECT p.id, p.display_name, p.email,
           COALESCE(a.status, 'sin_marcar')
      FROM public.user_careers uc
      JOIN public.profiles p ON p.id = uc.user_id
      LEFT JOIN public.attendance a
             ON a.career_id = p_career_id AND a.subject = p_subject
            AND a.class_date = p_class_date AND a.user_id = uc.user_id
     WHERE uc.career_id = p_career_id
     ORDER BY p.display_name NULLS LAST;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_attendance(
  p_career_id  TEXT,
  p_subject    TEXT,
  p_class_date DATE,
  p_user_id    UUID,
  p_status     TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_docente(p_career_id) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  IF p_status NOT IN ('presente', 'tarde', 'ausente', 'justificado') THEN
    RAISE EXCEPTION 'Estado inválido: %', p_status;
  END IF;

  INSERT INTO public.attendance
    (career_id, subject, class_date, user_id, status, marked_by, marked_at)
  VALUES
    (p_career_id, p_subject, p_class_date, p_user_id, p_status, auth.uid(), NOW())
  ON CONFLICT (career_id, subject, class_date, user_id) DO UPDATE
    SET status = EXCLUDED.status,
        marked_by = EXCLUDED.marked_by,
        marked_at = EXCLUDED.marked_at;
END;
$$;

REVOKE ALL ON FUNCTION public.is_docente(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_attendance_roster(TEXT, TEXT, DATE) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_attendance(TEXT, TEXT, DATE, UUID, TEXT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.is_docente(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_attendance_roster(TEXT, TEXT, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_attendance(TEXT, TEXT, DATE, UUID, TEXT) TO authenticated;

COMMIT;
