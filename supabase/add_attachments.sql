-- Вложения: имя файла и размер (для карточек и скачивания)
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS file_name text;
ALTER TABLE public.messages ADD COLUMN IF NOT EXISTS file_size bigint DEFAULT 0;