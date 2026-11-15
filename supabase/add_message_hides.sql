-- Удаление сообщений «только для себя».
--
-- Само сообщение остаётся в таблице messages: его видят остальные
-- участники. Здесь хранится список пар «сообщение + пользователь»,
-- которым это сообщение показывать не нужно. Так работает и в личке,
-- и в группе, и не зависит от того, кто отправитель.
--
-- Применить в Supabase Dashboard -> SQL Editor -> New query.
-- Без этой миграции приложение продолжит работать: «Удалить у себя»
-- покажет понятную ошибку, а чат загрузится как обычно.

create table if not exists public.message_hides (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  chat_id uuid not null references public.chats(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (message_id, user_id)
);

create index if not exists idx_message_hides_user_chat
  on public.message_hides(user_id, chat_id);

alter table public.message_hides enable row level security;

-- Доступ как у остальных таблиц MVP: только авторизованным.
drop policy if exists "open_all" on public.message_hides;
create policy "open_all" on public.message_hides
  for all to authenticated using (true) with check (true);

-- Чтобы «удалить у себя» сразу применялось на всех устройствах
-- пользователя, а не только после перезапуска.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'message_hides'
  ) then
    alter publication supabase_realtime add table public.message_hides;
  end if;
end $$;
