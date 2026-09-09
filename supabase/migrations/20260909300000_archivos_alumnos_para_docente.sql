-- Un alumno puede subir un archivo a su área personal sin que esté atado a
-- ninguna tarea oficial (p. ej. un trabajo extra para subir nota que ya
-- conversó con el docente fuera de la app). Hasta ahora ese archivo era
-- visible solo para el propio alumno: study_files_select únicamente deja
-- ver a un docente lo que es 'guia' compartida o lo que está adjunto a una
-- tarea oficial que él mismo creó — ninguna de las dos cubre este caso.
--
-- Este RPC, en vez de tocar esa política, sigue el mismo patrón ya usado
-- para progreso de tareas (get_task_submission_status): una función
-- SECURITY DEFINER acotada, que exige ser docente de la carrera y filtra
-- server-side a las asignaturas que el propio docente declaró impartir
-- (teacher_subjects) — mismo criterio que can_see_meeting_subject.
CREATE OR REPLACE FUNCTION public.get_student_uploads_for_teaching_subjects(
  p_career_id text
)
RETURNS TABLE(
  id text,
  name text,
  subject text,
  category text,
  description text,
  drive_link text,
  external_url text,
  user_id text,
  display_name text,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NOT public.is_docente(p_career_id) THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  RETURN QUERY
    SELECT sf.id, sf.name, sf.subject, sf.category, sf.description,
           sf.drive_link, sf.external_url, sf.user_id, p.display_name,
           sf.created_at
      FROM public.study_files sf
      JOIN public.profiles p ON p.id::text = sf.user_id
     WHERE sf.career_id = p_career_id
       AND sf.user_id <> auth.uid()::text
       AND EXISTS (
             SELECT 1 FROM public.teacher_subjects ts
              WHERE ts.user_id = auth.uid()
                AND ts.career_id = p_career_id
                AND ts.subject = sf.subject
           )
     ORDER BY sf.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_student_uploads_for_teaching_subjects(text)
  TO authenticated;
