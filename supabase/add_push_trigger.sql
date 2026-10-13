-- Автоматические push-уведомления о новых сообщениях
-- Выполнить ПОСЛЕ создания таблицы push_tokens (add_push.sql)

-- 1. Расширение для вызова Edge Function
create extension if not exists pg_net;

-- 2. URL проекта (current_setting('app.settings.supabase_url') в Supabase пуст)
create or replace function public.luxe_supabase_url()
returns text
language sql
immutable
as $$
  select coalesce(
    nullif(current_setting('app.settings.supabase_url', true), ''),
    'https://jdjgrczsnhroqjasipai.supabase.co'
  );
$$;

-- 3. Функция: собирает участников чата (кроме отправителя) и шлёт им push
create or replace function public.notify_new_message()
returns trigger
language plpgsql
security definer
as $$
declare
  v_sender uuid := NEW.sender_id;
  v_recipients uuid[];
  v_sender_name text;
begin
  select display_name into v_sender_name
  from public.profiles where id = v_sender;

  select coalesce(array_agg(user_id), '{}')
  into v_recipients
  from public.chat_members
  where chat_id = NEW.chat_id and user_id <> v_sender;

  if array_length(v_recipients, 1) is null then
    return NEW;
  end if;

  perform net.http_post(
    url := public.luxe_supabase_url() || '/functions/v1/send-push',
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := jsonb_build_object(
      'user_ids', to_jsonb(v_recipients),
      'title', coalesce(v_sender_name, 'Новое сообщение'),
      'body', left(coalesce(NEW.content, ''), 120),
      'chat_id', NEW.chat_id::text
    )
  );

  return NEW;
end;
$$;

-- 3. Триггер на INSERT в messages
drop trigger if exists on_message_created on public.messages;
create trigger on_message_created
  after insert on public.messages
  for each row execute function public.notify_new_message();