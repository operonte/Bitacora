-- La cuenta docente probó "Archivos de alumnos" y Drive le negó el acceso
-- ("solicitar acceso al propietario"): la fila en study_files ya era visible
-- por RLS/RPC, pero el archivo en Drive seguía siendo privado del alumno —
-- drive.file no le da a nadie más acceso hasta que el propio dueño (el
-- alumno, con su propia sesión) lo comparte, igual que ya pasa con un
-- archivo adjunto a una tarea oficial (ver task_details_dialog._attach).
--
-- Esta función deja que el cliente, en el momento de subir un archivo
-- personal, sepa si esa asignatura tiene un docente en la carrera — sin
-- decir quién es, solo si existe — para decidir si vale la pena abrir el
-- archivo en Drive (setLinkViewable) ahora que hay alguien que podría verlo.
CREATE OR REPLACE FUNCTION public.subject_has_teacher(p_career_id text, p_subject text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.teacher_subjects ts
     WHERE ts.career_id = p_career_id AND ts.subject = p_subject
  );
$$;

GRANT EXECUTE ON FUNCTION public.subject_has_teacher(text, text) TO authenticated;
