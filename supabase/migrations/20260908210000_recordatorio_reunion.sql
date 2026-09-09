-- Bitácora — recordatorio configurable por reunión.
--
-- El aviso de reunión avisaba siempre 5 minutos antes, fijo para todas.
-- Algunas reuniones (una clase presencial lejos, por ejemplo) necesitan más
-- margen. Se agrega una columna opcional: NULL sigue significando "usar el
-- default de la app" (5 minutos), así las reuniones ya creadas no cambian de
-- comportamiento.

BEGIN;

ALTER TABLE public.meetings
  ADD COLUMN IF NOT EXISTS reminder_minutes INTEGER;

COMMIT;
