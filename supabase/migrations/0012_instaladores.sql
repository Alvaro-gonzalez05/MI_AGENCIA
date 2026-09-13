-- =====================================================================
-- MI AGENCIA — 0012: instaladores para las actualizaciones automaticas
-- =====================================================================
-- Bucket PUBLICO con los instaladores de cada version y `ultima.json`, la
-- ficha que la app consulta para saber si hay una version nueva.
--
-- Publico a proposito: la app lo lee antes de iniciar sesion, y los
-- instaladores no contienen datos de ninguna agencia.
--
-- Nadie sube archivos desde la app: los sube el workflow de publicacion con
-- la clave de servicio, que no pasa por el RLS. Por eso no hace falta ninguna
-- politica de escritura.
--
-- El workflow tambien crea el bucket si no existe, asi que esta migracion es
-- para que el esquema quede documentado y reproducible, no un paso manual.
-- =====================================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('instaladores', 'instaladores', true, 52428800, null)
on conflict (id) do update set public = true;
