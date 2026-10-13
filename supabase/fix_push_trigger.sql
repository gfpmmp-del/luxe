-- Исправление триггера push: он больше НЕ может срывать отправку сообщений.
-- Выполнить в Supabase → SQL Editor → Run

-- 1. Убрать прежнюю (сломанную) версию
drop trigger if exists on_message_created on public.messages;
drop function if exists public.notify_new_message();

-- 2. URL проекта с надёжным значением по умолчанию
create or replace function public.luxe_supabase_url()
returns text
language sql
stable
as $$
  select coalesce(
    nullif(current_setting('app.settings.supabase_url', true), ''),
    'https://jdjgrczsnhroqjasipai.supabase.co'
  );
$$;

-- 3. Триггер, обёрнутый в обработчик ошибок:
--    если push не отправится — сообщение всё равно сохранится
create or replace function public.notify_new_message()
returns trigger
language plpgsql
security definer
as $$
declare
  v_recipients uuid[];
  v_sender_name text;
  v_url text;
begin
  begin
    select coalesce(array_agg(user_id), '{}')
      into v_recipients
      from public.chat_members
     where chat_id = NEW.chat_id and user_id <> NEW.sender_id;

    if array_length(v_recipients, 1) is null then
      return NEW;
    end if;

    select display_name into v_sender_name
      from public.profiles where id = NEW.sender_id;

    v_url := public.luxe_supabase_url();

    perform net.http_post(
      url := v_url || '/functions/v1/send-push',
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body := jsonb_build_object(
        'user_ids', to_jsonb(v_recipients),
        'title', coalesce(v_sender_name, 'Новое сообщение'),
        'body', left(coalesce(NEW.content, ''), 120),
        'chat_id', NEW.chat_id::text
      )
    );
  exception when others then
    -- КРИТИЧНО: глушим ошибку, иначе она откатывает вставку сообщения
    raise warning 'Luxe push не отправлен: %', sqlerrm;
  end;

  return NEW;
end;
$$;

-- 4. Создать триггер заново
create trigger on_message_created
  after insert on public.messages
  for each row execute function public.notify_new_message();

-- 5. Колонки для карточек вложений
alter table public.messages add column if not exists file_name text;
alter table public.messages add column if not exists file_size bigint default 0;