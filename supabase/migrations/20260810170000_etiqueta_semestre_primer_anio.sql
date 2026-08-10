-- Bitácora — etiqueta de semestre para las 16 materias de Primer Año
--
-- Estas las cargó el usuario a mano, con nombres propios (más cortos que
-- los del horario oficial), así que no calzaban por nombre exacto con la
-- migración anterior (20260810160000). El estado activo/inactivo que ya
-- tenían coincide 1 a 1 con Sem. I / Sem. II del horario (las 8 activas son
-- justo las de Sem. II), así que la etiqueta sale de ahí, no se adivina.

WITH etiquetas(name, semester) AS (
  VALUES
    ('Comunicación y redacción', 'Primer Año · Sem. I'),
    ('Contexto literario del A. T', 'Primer Año · Sem. I'),
    ('Griego 1', 'Primer Año · Sem. I'),
    ('Hebreo 1', 'Primer Año · Sem. I'),
    ('Hermenéutica', 'Primer Año · Sem. I'),
    ('Historia de Israel 1', 'Primer Año · Sem. I'),
    ('Introducción a la Historia de la Iglesia I', 'Primer Año · Sem. I'),
    ('Metodología de estudio', 'Primer Año · Sem. I'),

    ('Contexto literario del N.T', 'Primer Año · Sem. II'),
    ('Griego II', 'Primer Año · Sem. II'),
    ('Hebreo II', 'Primer Año · Sem. II'),
    ('Historia de iglesia II', 'Primer Año · Sem. II'),
    ('Historia de Israel II', 'Primer Año · Sem. II'),
    ('Introducción a la Teología Práctica', 'Primer Año · Sem. II'),
    ('Introducción a la Teología sistemática', 'Primer Año · Sem. II'),
    ('Palestina en tiempos de Jesus', 'Primer Año · Sem. II')
)
UPDATE public.careers c
SET predefined_subjects = (
  SELECT jsonb_agg(
    CASE
      WHEN et.semester IS NOT NULL THEN elem || jsonb_build_object('semester', et.semester)
      ELSE elem
    END
  )
  FROM jsonb_array_elements(c.predefined_subjects) AS elem
  LEFT JOIN etiquetas et ON et.name = elem->>'name'
)
WHERE c.id = 'teologia';

-- Verificación: debe dar 62 (46 de la migración anterior + 16 de Primer Año).
--
-- SELECT count(*) FROM public.careers c, jsonb_array_elements(c.predefined_subjects) e
-- WHERE c.id = 'teologia' AND e->>'semester' IS NOT NULL;
