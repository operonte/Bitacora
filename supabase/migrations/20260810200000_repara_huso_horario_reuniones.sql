-- Bitácora — repara la hora de las reuniones existentes (bug de huso horario)
--
-- Meeting.toMap() mandaba meetingDate.toIso8601String() sin marca de huso.
-- meetings.meeting_date es timestamptz, así que Postgres interpretaba esa
-- hora local (ej. 19:00 Chile) como si fuera UTC, guardando el instante
-- equivocado (19:00 UTC = 15:00 Chile real). El código ya se corrigió
-- (lib/models/meeting_model.dart, toUtc()/toLocal() explícitos); esto repara
-- las filas que ya existían, reinterpretando la hora guardada como si fuera
-- de America/Santiago en vez de UTC.
--
-- El truco (`AT TIME ZONE 'UTC'` seguido de `AT TIME ZONE 'America/Santiago'`)
-- extrae el reloj de pared tal como quedó guardado y lo reinterpreta en el
-- huso correcto, usando el tzdata real de Postgres — contempla cualquier
-- cambio de horario de verano sin necesidad de un offset fijo a mano.

UPDATE public.meetings
SET meeting_date = (meeting_date AT TIME ZONE 'UTC') AT TIME ZONE 'America/Santiago'
WHERE meeting_date IS NOT NULL;

-- Verificación: la reunión "Culto apertura" debe quedar en 2026-08-10 23:00:00+00
-- (19:00 Chile), no en 2026-08-10 19:00:00+00 como estaba.
--
-- SELECT title, meeting_date FROM public.meetings WHERE title = 'Culto apertura';
