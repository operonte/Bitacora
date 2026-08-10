-- Bitácora — carga la malla curricular de Informática (11 trimestres)
--
-- Tres de las materias ya existían con profesor real (Álgebra, Fundamentos
-- de gestión, Probabilidad y estadística) — se les agrega solo la etiqueta
-- de semestre, sin tocar profesor ni estado, para no duplicarlas. Las 36
-- restantes son nuevas: profesor "Por definir" (la malla no trae nombres,
-- se completa después a mano) y todas **inactivas** — no se confirmó qué
-- trimestre está en curso, así que se evita activar el que no corresponde.
-- Se activa el que sea con el filtro por trimestre + "Activar todas" que ya
-- tiene el panel admin.

WITH nuevas(name, semester) AS (
  VALUES
    ('Electivo de Comunicación 1', 'Primer Año · 1er Trimestre'),

    ('Cálculo', 'Primer Año · 2do Trimestre'),
    ('Inferencia Estadísticas', 'Primer Año · 2do Trimestre'),
    ('Fundamentos de Bases de Datos', 'Primer Año · 2do Trimestre'),
    ('Electivo de Comunicación 2', 'Primer Año · 2do Trimestre'),

    ('Programación', 'Primer Año · 3er Trimestre'),
    ('Bases de Hadware y Softwares', 'Primer Año · 3er Trimestre'),
    ('Finanzas', 'Primer Año · 3er Trimestre'),
    ('Inglés I', 'Primer Año · 3er Trimestre'),

    ('Programación Orientada a Objetos', 'Segundo Año · 4to Trimestre'),
    ('Bases de Datos Relacionales', 'Segundo Año · 4to Trimestre'),
    ('Sistemas Operativos', 'Segundo Año · 4to Trimestre'),
    ('Inglés II', 'Segundo Año · 4to Trimestre'),

    ('Metodologías Lean Diseño Sistemas', 'Segundo Año · 5to Trimestre'),
    ('Bases de Datos No Estructuradas', 'Segundo Año · 5to Trimestre'),
    ('Testeo Softwares', 'Segundo Año · 5to Trimestre'),
    ('Inglés III', 'Segundo Año · 5to Trimestre'),

    ('Programación Front End', 'Segundo Año · 6to Trimestre'),
    ('Ingeniería de Softwares', 'Segundo Año · 6to Trimestre'),
    ('Electivo Innovación y Emprendimiento', 'Segundo Año · 6to Trimestre'),
    ('Inglés IV', 'Segundo Año · 6to Trimestre'),

    ('Programación Back End', 'Tercer Año · 7mo Trimestre'),
    ('Arquitectura y Redes de Datos', 'Tercer Año · 7mo Trimestre'),
    ('Diseño de Sistemas', 'Tercer Año · 7mo Trimestre'),
    ('Electivo de Ética', 'Tercer Año · 7mo Trimestre'),

    ('Minería de Datos', 'Tercer Año · 8vo Trimestre'),
    ('Servicios Cloud', 'Tercer Año · 8vo Trimestre'),
    ('Inteligencia Artificial', 'Tercer Año · 8vo Trimestre'),
    ('Gestión de Calidad Proyectos TI', 'Tercer Año · 8vo Trimestre'),

    ('Big Data', 'Tercer Año · 9no Trimestre'),
    ('Machine Learning', 'Tercer Año · 9no Trimestre'),
    ('Ciberseguridad', 'Tercer Año · 9no Trimestre'),
    ('Iot y Desarrollo Aplicaciones', 'Tercer Año · 9no Trimestre'),

    ('Bootcamp TI – Desarrollador Full Stack (Minor)', 'Cuarto Año · 10mo Trimestre'),
    ('Proyecto Título', 'Cuarto Año · 10mo Trimestre'),

    ('Práctica Profesional', 'Cuarto Año · 11vo Trimestre')
),
etiquetas(name, semester) AS (
  VALUES
    ('Álgebra', 'Primer Año · 1er Trimestre'),
    ('Fundamentos de gestión', 'Primer Año · 1er Trimestre'),
    ('Probabilidad y estadística', 'Primer Año · 1er Trimestre')
),
armadas AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', 'subj_' || replace(gen_random_uuid()::text, '-', ''),
      'name', name,
      'professor', 'Por definir',
      'description', NULL,
      'visibility', 0,
      'allowedUsers', '[]'::jsonb,
      'userId', 'system',
      'userName', 'Sistema',
      'createdAt', (extract(epoch from now()) * 1000)::bigint,
      'isActive', false,
      'semester', semester
    )
  ) AS materias
  FROM nuevas
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
) || (SELECT materias FROM armadas)
WHERE c.id = 'custom_1785185480271';

-- Verificación: debe dar 4 (las que ya había) + 36 (nuevas) = 40.
--
-- SELECT jsonb_array_length(predefined_subjects) FROM public.careers WHERE id = 'custom_1785185480271';
