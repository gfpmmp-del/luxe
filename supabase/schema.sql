-- Luxe Messenger — Supabase schema
-- Выполнить в Supabase Dashboard -> SQL Editor -> New query

-- 1. Профили (1 к 1 с auth.users)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  display_name text not null,
  avatar_url text,
  status text default 'offline',
  last_seen timestamptz default now()
);

-- 2. Чаты (личные и групповые)
create table if not exists public.chats (
  id uuid primary key default gen_random_uuid(),
  is_group boolean default false,
  kind text default 'direct', -- direct | group | channel
  title text,
  description text default '',
  avatar_url text,
  created_at timestamptz default now(),
  created_by uuid references public.profiles(id)
);

-- 3. Участники чата
create table if not exists public.chat_members (
  chat_id uuid references public.chats(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  joined_at timestamptz default now(),
  primary key (chat_id, user_id)
);

-- 4. Сообщения
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  chat_id uuid references public.chats(id) on delete cascade,
  sender_id uuid references public.profiles(id) on delete cascade,
  content text not null default '',
  type text not null default 'text', -- text | image | system
  file_url text,
  created_at timestamptz default now()
);
create index if not exists idx_messages_chat on public.messages(chat_id, created_at desc);

-- 5. Сигналинг звонков (WebRTC через Realtime)
create table if not exists public.call_signals (
  id uuid primary key default gen_random_uuid(),
  caller_id uuid references public.profiles(id) on delete cascade,
  callee_id uuid references public.profiles(id) on delete cascade,
  chat_id uuid references public.chats(id) on delete cascade,
  type text not null, -- offer | answer | ice | hangup | reject
  payload jsonb not null default '{}',
  created_at timestamptz default now()
);
create index if not exists idx_signals_callee on public.call_signals(callee_id, created_at desc);

-- 6. Включаем Realtime для таблиц
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.call_signals;
alter publication supabase_realtime add table public.profiles;

-- 7. RLS: для MVP разрешаем всё авторизованным (потом ужесточим)
alter table public.profiles enable row level security;
alter table public.chats enable row level security;
alter table public.chat_members enable row level security;
alter table public.messages enable row level security;
alter table public.call_signals enable row level security;

drop policy if exists "open_all" on public.profiles;
drop policy if exists "open_all" on public.chats;
drop policy if exists "open_all" on public.chat_members;
drop policy if exists "open_all" on public.messages;
drop policy if exists "open_all" on public.call_signals;

create policy "open_all" on public.profiles for all to authenticated using (true) with check (true);
create policy "open_all" on public.chats for all to authenticated using (true) with check (true);
create policy "open_all" on public.chat_members for all to authenticated using (true) with check (true);
create policy "open_all" on public.messages for all to authenticated using (true) with check (true);
create policy "open_all" on public.call_signals for all to authenticated using (true) with check (true);

-- 8. Storage для аватаров и картинок: создать bucket 'chat-media' (public) в Dashboard -> Storage
-- insert policy для storage делается в интерфейсе: сделать bucket Public.
-- 9. Storage-политики (иначе загрузка аватарок упадёт с RLS-ошибкой):
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
