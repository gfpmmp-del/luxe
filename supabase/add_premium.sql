-- Luxe Premium
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS premium BOOLEAN DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS premium_until TIMESTAMPTZ;

-- История покупок/подписок (для будущей оплаты)
create table if not exists public.premium_orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  plan text not null default 'month', -- month | year
  price integer not null default 0,
  started_at timestamptz default now(),
  expires_at timestamptz,
  status text default 'active' -- active | expired | revoked
);
create index if not exists idx_premium_orders_user on public.premium_orders(user_id);

alter table public.premium_orders enable row level security;

drop policy if exists "premium_own" on public.premium_orders;
create policy "premium_own" on public.premium_orders
  for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());