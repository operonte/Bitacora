-- Logo por carrera, lo pone el súper usuario desde Administración. Solo la
-- URL (el archivo en sí vive en Drive, igual que el resto de los archivos
-- de la app) — sin RLS nueva: careers ya solo deja escribir a administradores
-- (careers_admin_write, is_admin()).
ALTER TABLE public.careers
  ADD COLUMN IF NOT EXISTS logo_url text;
