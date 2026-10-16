-- Ссылки, сохранённые во время работы через Cloudflare Worker.
--
-- Пока приложение ходило на прокси, в базу писались адреса вида
-- https://luxe-proxy.gfpmmp.workers.dev/storage/v1/object/public/...
-- Эти файлы лежат в том же бакете и по-прежнему доступны, но адрес
-- воркера их больше не отдаёт — медиа перестало открываться.
--
-- Приложение чинит такие ссылки само, при чтении. Этот скрипт нужен,
-- чтобы привести саму базу в порядок: старые ссылки перестанут
-- попадать в новые сообщения и в выгрузку данных.
--
-- Выполнить в Supabase Dashboard -> SQL Editor -> New query.

update public.messages
   set file_url = replace(file_url, 'https://luxe-proxy.gfpmmp.workers.dev',
                                  'https://jdjgrczsnhroqjasipai.supabase.co')
 where file_url like '%luxe-proxy.gfpmmp.workers.dev%';

update public.profiles
   set avatar_url = replace(avatar_url, 'https://luxe-proxy.gfpmmp.workers.dev',
                                    'https://jdjgrczsnhroqjasipai.supabase.co')
 where avatar_url like '%luxe-proxy.gfpmmp.workers.dev%';

update public.chats
   set avatar_url = replace(avatar_url, 'https://luxe-proxy.gfpmmp.workers.dev',
                                    'https://jdjgrczsnhroqjasipai.supabase.co')
 where avatar_url like '%luxe-proxy.gfpmmp.workers.dev%';

update public.stickers
   set url = replace(url, 'https://luxe-proxy.gfpmmp.workers.dev',
                            'https://jdjgrczsnhroqjasipai.supabase.co')
 where url like '%luxe-proxy.gfpmmp.workers.dev%';
