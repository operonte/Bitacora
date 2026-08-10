-- Bitácora — etiqueta de semestre en las materias que se cargaron por script
--
-- Subject.semester es un campo nuevo, solo para que el panel admin muestre a
-- qué semestre pertenece cada materia. No toca Primer Año a propósito: esas
-- 16 las cargó el usuario a mano, con sus propios nombres, y no hay forma
-- confiable de hacer calzar el nombre exacto sin arriesgar una etiqueta
-- equivocada. Las 46 de Segundo a Cuarto Año sí, porque los nombres son
-- los mismos que se insertaron en la migración anterior.

WITH etiquetas(name, semester) AS (
  VALUES
    ('Introducción a la Sociología', 'Segundo Año · Sem. III'),
    ('Teología Pastoral', 'Segundo Año · Sem. III'),
    ('Teología Sistemática I', 'Segundo Año · Sem. III'),
    ('Griego Bíblico III', 'Segundo Año · Sem. III'),
    ('Introducción a la Psicología', 'Segundo Año · Sem. III'),
    ('Historia del Cristianismo III: Pre reformadores', 'Segundo Año · Sem. III'),
    ('Introducción a la Filosofía', 'Segundo Año · Sem. III'),
    ('Hebreo Bíblico III', 'Segundo Año · Sem. III'),

    ('Ética Cristiana', 'Segundo Año · Sem. IV'),
    ('Teología Sistemática II', 'Segundo Año · Sem. IV'),
    ('Nuevo Testamento I (Evangelios)', 'Segundo Año · Sem. IV'),
    ('Hebreo IV', 'Segundo Año · Sem. IV'),
    ('Educación Cristiana', 'Segundo Año · Sem. IV'),
    ('Historia de la Iglesia IV: Reforma Protestante, Siglo XVI', 'Segundo Año · Sem. IV'),
    ('Griego IV', 'Segundo Año · Sem. IV'),
    ('Antiguo Testamento I', 'Segundo Año · Sem. IV'),

    ('Antropología Cristiana', 'Tercer Año · Sem. V'),
    ('Antiguo Testamento II', 'Tercer Año · Sem. V'),
    ('Historia de la Iglesia V: La iglesia en el siglo XX', 'Tercer Año · Sem. V'),
    ('Hebreo Bíblico V', 'Tercer Año · Sem. V'),
    ('Metodología de la Investigación Científica', 'Tercer Año · Sem. V'),
    ('Teología Sistemática III', 'Tercer Año · Sem. V'),
    ('Nuevo Testamento II', 'Tercer Año · Sem. V'),
    ('Griego Bíblico V', 'Tercer Año · Sem. V'),

    ('Seminario de la Historia y Realidad Latinoamericana', 'Tercer Año · Sem. VI'),
    ('Liturgia y Predicación', 'Tercer Año · Sem. VI'),
    ('Historia de la Iglesia VI: La Iglesia en Chile', 'Tercer Año · Sem. VI'),
    ('Antiguo Testamento III', 'Tercer Año · Sem. VI'),
    ('Corrientes Teológicas Cristianas', 'Tercer Año · Sem. VI'),
    ('Nuevo Testamento III (Cartas Joánicas)', 'Tercer Año · Sem. VI'),
    ('Hebreo VI', 'Tercer Año · Sem. VI'),
    ('Griego VI', 'Tercer Año · Sem. VI'),

    ('Teología del Antiguo Testamento', 'Cuarto Año · Sem. VII'),
    ('Exégesis y Hermenéutica del AT', 'Cuarto Año · Sem. VII'),
    ('Teología y Medio Ambiente', 'Cuarto Año · Sem. VII'),
    ('Hebreo Bíblico VII', 'Cuarto Año · Sem. VII'),
    ('Griego Bíblico VII', 'Cuarto Año · Sem. VII'),
    ('Filosofía de la Religión', 'Cuarto Año · Sem. VII'),
    ('Religiones Comparadas y Diálogo Interreligioso', 'Cuarto Año · Sem. VII'),

    ('Género y Teología (Hermenéutica Feminista de la Biblia)', 'Cuarto Año · Sem. VIII'),
    ('Exégesis y Hermenéutica del N.T.', 'Cuarto Año · Sem. VIII'),
    ('Teología del Nuevo Testamento', 'Cuarto Año · Sem. VIII'),
    ('Griego VIII', 'Cuarto Año · Sem. VIII'),
    ('Teólogos Contemporáneos', 'Cuarto Año · Sem. VIII'),
    ('Seminario de fe y razón e ideología y fenomenología de la religión', 'Cuarto Año · Sem. VIII'),
    ('Hebreo VIII', 'Cuarto Año · Sem. VIII')
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

-- Verificación: debe dar 46.
--
-- SELECT count(*) FROM public.careers c, jsonb_array_elements(c.predefined_subjects) e
-- WHERE c.id = 'teologia' AND e->>'semester' IS NOT NULL;
