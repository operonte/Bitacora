-- Bitácora — el alumno puede ver su propia asistencia.
--
-- `attendance` no tiene políticas RLS propias a propósito (ver
-- 20260906160000_asistencia.sql): todo el acceso pasa por RPC SECURITY
-- DEFINER. Hasta ahora las dos que existían (get_attendance_roster,
-- set_attendance) exigían ser docente — el alumno marcado no tenía ninguna
-- forma de consultar su propio registro. Esta no necesita ese chequeo: el
-- filtro por auth.uid() ya limita el resultado a filas propias, sea quien
-- sea quien llame.

BEGIN;

CREATE OR REPLACE FUNCTION public.get_my_attendance(p_career_id TEXT)
RETURNS TABLE (
  subject    TEXT,
  class_date DATE,
  status     TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT subject, class_date, status
    FROM public.attendance
   WHERE career_id = p_career_id AND user_id = auth.uid()
   ORDER BY class_date DESC;
$$;

REVOKE ALL ON FUNCTION public.get_my_attendance(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_my_attendance(TEXT) TO authenticated;

COMMIT;
