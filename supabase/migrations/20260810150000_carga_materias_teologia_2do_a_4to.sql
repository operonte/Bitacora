-- Bitácora — carga materias de Teología, Segundo a Cuarto Año
--
-- Primer Año ya estaba cargado a mano desde el panel admin (16 materias,
-- 8 activas del semestre en curso). Esto agrega las 46 que faltan de
-- Segundo, Tercer y Cuarto Año — las 6 hojas de horario que pasó el usuario
-- (materias_teologia_2026.md, que se borra aparte) — sin tocar lo que ya
-- había. Quedan activas las del semestre en curso (Sem. IV/VI/VIII,
-- "segundo semestre" de cada año) e inactivas las que ya pasaron
-- (Sem. III/V/VII), mismo criterio que ya se usó para Primer Año.

WITH nuevas(name, professor, is_active) AS (
  VALUES
    -- Segundo Año · Sem. III (pasado, inactivas)
    ('Introducción a la Sociología', 'Drs. Karina Ojeda', false),
    ('Teología Pastoral', 'Dra. Gloria Rojas', false),
    ('Teología Sistemática I', 'Dra. Elizabeth Salazar Sanzana', false),
    ('Griego Bíblico III', 'Lic. Samuel Restrepo', false),
    ('Introducción a la Psicología', 'Lic. Marcela Ibacache', false),
    ('Historia del Cristianismo III: Pre reformadores', 'Lic. Carmen Grandón Q.', false),
    ('Introducción a la Filosofía', 'Mg. Germán Quintana', false),
    ('Hebreo Bíblico III', 'Lic. Hemir Ochoa', false),

    -- Segundo Año · Sem. IV (en curso, activas)
    ('Ética Cristiana', 'Mg. Claudio Colombo', true),
    ('Teología Sistemática II', 'Dra. Elizabeth Salazar Sanzana', true),
    ('Nuevo Testamento I (Evangelios)', 'Dr. Javier Ortega', true),
    ('Hebreo IV', 'Mg. Gustavo Robles', true),
    ('Educación Cristiana', 'Lic. Eduardo Vidal', true),
    ('Historia de la Iglesia IV: Reforma Protestante, Siglo XVI', 'Lic. Carmen Grandón Quilodrán', true),
    ('Griego IV', 'Lic. Samuel Restrepo', true),
    ('Antiguo Testamento I', 'Mg. Jaime Alarcón Véjar', true),

    -- Tercer Año · Sem. V (pasado, inactivas)
    ('Antropología Cristiana', 'Dr. Nicolás Panotto', false),
    ('Antiguo Testamento II', 'Mg. Jaime Alarcón', false),
    ('Historia de la Iglesia V: La iglesia en el siglo XX', 'Mg. Juan Ortiz R.', false),
    ('Hebreo Bíblico V', 'Lic. Gustavo Robles', false),
    ('Metodología de la Investigación Científica', 'Mg. Claudia Mardones', false),
    ('Teología Sistemática III', 'Dra. Elizabeth Salazar', false),
    ('Nuevo Testamento II', 'Dr. Javier Ortega', false),
    ('Griego Bíblico V', 'Lic. Samuel Restrepo', false),

    -- Tercer Año · Sem. VI (en curso, activas)
    ('Seminario de la Historia y Realidad Latinoamericana', 'Drs. Karina Ojeda', true),
    ('Liturgia y Predicación', 'Lic. Miguel Ulloa', true),
    ('Historia de la Iglesia VI: La Iglesia en Chile', 'Mg. Cecilia Castillo Nanjarí', true),
    ('Antiguo Testamento III', 'Mg. Jaime Alarcón Véjar', true),
    ('Corrientes Teológicas Cristianas', 'Mg. Gustavo Robles', true),
    ('Nuevo Testamento III (Cartas Joánicas)', 'Dr. Javier Ortega', true),
    ('Hebreo VI', 'Mg. Gustavo Robles', true),
    ('Griego VI', 'Lic. Samuel Restrepo', true),

    -- Cuarto Año · Sem. VII (pasado, inactivas)
    ('Teología del Antiguo Testamento', 'Mg. Jaime Alarcón Véjar', false),
    ('Exégesis y Hermenéutica del AT', 'Mg. Jaime Alarcón', false),
    ('Teología y Medio Ambiente', 'Mg. Arianne van Andel', false),
    ('Hebreo Bíblico VII', 'Lic. Gustavo Robles', false),
    ('Griego Bíblico VII', 'Lic. Samuel Restrepo', false),
    ('Filosofía de la Religión', 'Mg. Claudio Colombo', false),
    ('Religiones Comparadas y Diálogo Interreligioso', 'Dr. Daniel Godoy F.', false),

    -- Cuarto Año · Sem. VIII (en curso, activas)
    ('Género y Teología (Hermenéutica Feminista de la Biblia)', 'Mg. Cecilia Castillo', true),
    ('Exégesis y Hermenéutica del N.T.', 'Dr. Daniel Godoy', true),
    ('Teología del Nuevo Testamento', 'Lic. Carlos Caamaño Espinoza', true),
    ('Griego VIII', 'Lic. Samuel Restrepo', true),
    ('Teólogos Contemporáneos', 'Dra. Elizabeth Salazar Sanzana', true),
    ('Seminario de fe y razón e ideología y fenomenología de la religión', 'Mg. Claudio Colombo', true),
    ('Hebreo VIII', 'Mg. Gustavo Robles', true)
),
armadas AS (
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', 'subj_' || replace(gen_random_uuid()::text, '-', ''),
      'name', name,
      'professor', professor,
      'description', NULL,
      'visibility', 0,
      'allowedUsers', '[]'::jsonb,
      'userId', 'system',
      'userName', 'Sistema',
      'createdAt', (extract(epoch from now()) * 1000)::bigint,
      'isActive', is_active
    )
  ) AS materias
  FROM nuevas
)
UPDATE public.careers
SET predefined_subjects = predefined_subjects || (SELECT materias FROM armadas)
WHERE id = 'teologia';

-- Verificación:
--
-- SELECT jsonb_array_length(predefined_subjects) FROM public.careers WHERE id = 'teologia';
-- -- Debe dar 16 (ya cargadas) + 46 (nuevas) = 62.
