-- Bitácora — repara materias predefinidas sin id
--
-- Subject.toMap() (lib/models/subject_model.dart) nunca incluyó 'id' en el
-- mapa que se guarda: cada vez que se agregaba, editaba o borraba una materia
-- predefinida, _persistCareerSubjects() reescribía el array entero de
-- careers.predefined_subjects vía toMap(), y todas las materias —no solo la
-- tocada— perdían su id al guardarse. Al releer, Subject.fromMap() las
-- devolvía con id null, y career_subjects_screen.dart usa materia.id! para
-- editar o borrar: de ahí el "Null check operator used on a null value".
--
-- El código ya se corrigió (toMap() ahora incluye id). Esto repara el dato
-- que ya quedó sin id en producción, dándole uno nuevo a cada materia que no
-- lo tenga. El nombre y el resto de los campos no cambian.

UPDATE public.careers
SET predefined_subjects = (
  SELECT jsonb_agg(
    CASE
      WHEN elem->>'id' IS NULL OR elem->>'id' = ''
        THEN elem || jsonb_build_object('id', 'subj_' || replace(gen_random_uuid()::text, '-', ''))
      ELSE elem
    END
  )
  FROM jsonb_array_elements(predefined_subjects) AS elem
)
WHERE predefined_subjects IS NOT NULL
  AND jsonb_array_length(predefined_subjects) > 0;

-- Verificación: debe dar 0 filas.
--
-- SELECT id FROM public.careers c
-- WHERE EXISTS (
--   SELECT 1 FROM jsonb_array_elements(c.predefined_subjects) e
--   WHERE e->>'id' IS NULL OR e->>'id' = ''
-- );
