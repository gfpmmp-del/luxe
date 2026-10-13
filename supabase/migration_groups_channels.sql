-- Luxe: группы, каналы, аватары (миграция для существующего проекта)
-- Supabase Dashboard -> SQL Editor -> New query -> вставить -> Run

-- 1. Тип чата и описание (старые строки без kind обрабатываются кодом как раньше)
alter table public.chats add column if not exists kind text default 'direct';
alter table public.chats add column if not exists description text default '';

-- Backfill: существующие групповые чаты помечаем как group
update public.chats set kind = 'group' where is_group = true and (kind is null or kind = 'direct');

-- 2. Storage-политики для bucket 'chat-media' (без них загрузка аватарок упадёт с RLS-ошибкой)
drop policy if exists "public_read" on storage.objects;
drop policy if exists "auth_upload" on storage.objects;
drop policy if exists "auth_update" on storage.objects;
drop policy if exists "auth_delete" on storage.objects;

create policy "public_read" on storage.objects
  for select to anon, authenticated using (bucket_id = 'chat-media');
create policy "auth_upload" on storage.objects
  for insert to authenticated with check (bucket_id = 'chat-media');
create policy "auth_update" on storage.objects
  for update to authenticated using (bucket_id = 'chat-media');
create policy "auth_delete" on storage.objects
  for delete to authenticated using (bucket_id = 'chat-media');
