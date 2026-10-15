-- Голосовые сообщения, видеокружки и стикеры.
-- Выполнить в Supabase Dashboard -> SQL Editor -> New query.

-- 1. Голосовые и кружки: длительность и форма звуковой волны.
--    Без этих колонок сообщение отправить нельзя, но старые сообщения
--    остаются рабочими (значения по умолчанию).
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS duration integer DEFAULT 0;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS waveform text;

-- 2. Наборы стикеров пользователя.
create table if not exists public.stickers (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  emoji text not null default '',
  url text not null,
  kind text not null default 'static', -- static | gif | lottie
  created_at timestamptz default now()
);
create index if not exists idx_stickers_owner
  on public.stickers(owner_id, created_at desc);

-- 3. Realtime: собеседник должен увидеть отправленный стикер сразу.
do $$
begin
  alter publication supabase_realtime add table public.stickers;
exception when duplicate_object then null;
end $$;

-- 4. RLS
alter table public.stickers enable row level security;
drop policy if exists "open_all" on public.stickers;
create policy "open_all" on public.stickers for all
  using (true) with check (true);
