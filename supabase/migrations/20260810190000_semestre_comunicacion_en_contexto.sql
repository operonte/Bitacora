-- Bitácora — etiqueta de semestre para "Comunicación en contexto"
--
-- Cuarta materia que ya existía en Informática antes de la carga de la
-- malla (20260810180000): no calzaba por nombre con ninguna del PDF, pero
-- el usuario confirmó que también es de Primer Año · 1er Trimestre.

UPDATE public.careers
SET predefined_subjects = (
  SELECT jsonb_agg(
    CASE
      WHEN elem->>'name' = 'Comunicación en contexto'
        THEN elem || jsonb_build_object('semester', 'Primer Año · 1er Trimestre')
      ELSE elem
    END
  )
  FROM jsonb_array_elements(predefined_subjects) AS elem
)
WHERE id = 'custom_1785185480271';
