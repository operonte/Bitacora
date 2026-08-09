-- Bitácora — endurecimiento 20: inscribir a alguien en una carrera
--
-- Hasta ahora la única forma de entrar a una carrera era escribir su clave de
-- acceso. Eso obliga a repartir la clave para dar de alta a una persona, y una
-- vez repartida no se puede retirar de las manos de nadie: quitar a alguien
-- desde el panel no le impide volver a entrar con la misma clave.
--
-- Con esto un administrador puede inscribir a una cuenta directamente, sin que
-- la clave salga a pasear. Es además lo que permite ofrecer "Deshacer" tras
-- quitar a un miembro por error, que es como se descubre que hacía falta.

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_add_member(
  p_career_id TEXT,
  p_user_id   UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'No autorizado';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.careers WHERE id = p_career_id) THEN
    RAISE EXCEPTION 'La carrera % no existe', p_career_id;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'Esa cuenta no existe';
  END IF;

  INSERT INTO public.user_careers (user_id, career_id)
  VALUES (p_user_id, p_career_id)
  ON CONFLICT (user_id, career_id) DO NOTHING;
END;
$$;

REVOKE ALL  ON FUNCTION public.admin_add_member(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_add_member(TEXT, UUID) TO authenticated;

COMMIT;
