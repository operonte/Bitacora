-- Bitácora — anuncios visibles por toda la carrera, aunque tuvieran
-- asignatura puesta: announcements_select solo comprobaba pertenencia a la
-- carrera, nunca la asignatura. Confirmado explícito por el usuario: un
-- anuncio de una asignatura es solo para el curso que la estudia, no para
-- toda la carrera — un anuncio sin asignatura (subject IS NULL) sigue
-- siendo "para toda la carrera", como dice el comentario original de la
-- tabla.
--
-- Mismo cruce por semestre que ya usa material docente compartido
-- (can_see_shared_subject_content): si la asignatura tiene semestre
-- cargado, solo los alumnos de ese semestre; si no, se degrada a toda la
-- carrera. Quien lo creó siempre lo ve, aunque su propio semestre (o el de
-- un docente, que no tiene) no calce — sin esto, un docente podía dejar de
-- ver su propio anuncio.

BEGIN;

DROP POLICY IF EXISTS "announcements_select" ON public.announcements;
CREATE POLICY "announcements_select" ON public.announcements
  FOR SELECT USING (
    announcements.created_by = auth.uid()
    OR (
      CASE
        WHEN announcements.subject IS NULL THEN
          EXISTS (
            SELECT 1 FROM public.user_careers uc
             WHERE uc.user_id = auth.uid()
               AND uc.career_id = announcements.career_id
          )
        ELSE
          public.can_see_shared_subject_content(
            announcements.career_id,
            announcements.subject
          )
      END
    )
  );

COMMIT;
