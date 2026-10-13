-- Добавить колонку статуса сообщений (для удаления и прочтения)
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS status text DEFAULT 'sent';
