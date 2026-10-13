-- Верификация пользователей: галочка рядом с именем
-- Колонка verified уже могла быть добавлена ранее (add_verified.sql),
-- IF NOT EXISTS делает скрипт безопасным для повторного запуска.
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS verified boolean DEFAULT false;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_admin boolean DEFAULT false;

-- Назначить себя администратором (замени username на свой):
-- UPDATE public.profiles SET is_admin = true WHERE username = 'твой_username';

-- Выдать галочку конкретному пользователю:
-- UPDATE public.profiles SET verified = true WHERE username = 'другой_username';