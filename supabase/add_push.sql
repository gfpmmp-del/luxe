-- Push-уведомления: токены устройств
create table if not exists public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null unique,
  platform text default 'android', -- android | ios | windows | web
  created_at timestamptz default now()
);
create index if not exists idx_push_tokens_user on public.push_tokens(user_id);

alter table public.push_tokens enable row level security;

drop policy if exists "push_own" on public.push_tokens;
create policy "push_own" on public.push_tokens
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());