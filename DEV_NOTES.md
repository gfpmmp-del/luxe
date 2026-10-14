# Заметки по процессу разработки

## Правило: после любой правки пушить в GitHub

```
git add -A
git commit -m "описание"
git push origin master
```

Codemagic подписан на webhook и сам запускает iOS-сборку при каждом пуше.
Без push новая версия в облако не попадёт.

Ветка называется `master` (не `main`).

## Сборка iOS без Mac

- Codemagic, тариф Individual: 500 минут macOS M2 в месяц бесплатно
- Workflow: `iOS unsigned` (release без подписи)
- Артефакт: `luxe.ipa` → ставится через Sideloadly (подпись живёт 7 дней)
- Конфиг: `codemagic.yaml` в корне репозитория

### Важное про `.gitignore`

`third_party/firebase_core` НЕЛЬЗЯ исключать из git.
Это локальная копия firebase_core без секции `windows`
(на Windows она тянет ~4 ГБ SDK, а FCM на Windows не работает).
Без неё сборка падает:
`could not find package firebase_core at "third_party/firebase_core"`

Также не исключать:
- `codemagic.yaml`
- `ios/Runner/Info.plist` (там разрешения камеры и микрофона)

Исключено и не должно возвращаться в репозиторий:
- `android/app/google-services.json` (ключ Firebase)
- `ios/Runner/GoogleService-Info.plist` (его добавишь позже для пушей)
- `assets/logo/sizes/` (генерируется `tools/gen_icons.ps1`)
- `build/`, `.dart_tool/`, `windows/flutter/ephemeral/`

## Сборки на Windows

```cmd
flutter build windows --release
```
Результат — папка `build\windows\x64\runner\Release\`.
Копировать в zip нужно **всю папку**: exe без DLL и `data` не запустится.

## База данных (Supabase)

Файлы миграций в `supabase/`:
- `add_push.sql` — таблица push_tokens
- `fix_push_trigger.sql` — починка триггера (старый ломал отправку)
- `add_verified.sql` — verified + is_admin
- `add_premium.sql` — premium + premium_orders
- `add_attachments.sql` — file_name + file_size

Триггер на messages обёрнут в `exception when others` — он не должен
ломать отправку сообщений, даже если Edge Function недоступна.