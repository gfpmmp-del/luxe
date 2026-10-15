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
- `add_voice_stickers.sql` — **обязательно применить перед отправкой
  голосовых, кружков и стикеров**: duration + waveform в messages,
  таблица stickers

Триггер на messages обёрнут в `exception when others` — он не должен
ломать отправку сообщений, даже если Edge Function недоступна.

## Голосовые, кружки и стикеры

Типы сообщений: `voice`, `circle`, `sticker`.

Колонки `duration` и `waveform` пишутся **отдельным UPDATE** после вставки,
как `file_name`. Причина та же: если миграция не применена, INSERT с этими
полями упал бы целиком и сообщение не отправилось бы вообще.

Волна хранится строкой из цифр 0–9 (48 символов = пики по всему Голосовому),
а не JSON-массивом: колонка остаётся лёгкой, а на разбор уходит `VoiceService.unpackWaveform`.

Стикеры лежат в bucket `chat-media` по пути `stickers/`, отдельный бакет
не заводим — лишний шаг в панели Supabase.

`.tgs` — это zip, Lottie его не читает: такие файлы показываются заглушкой.
Поддерживается голый `.json` (Lottie), `.gif` и статика (PNG/JPG/WebP).

## Звонки: звук

Звук настраивается **только** средствами flutter_webrtc
(`Helper.setAndroidAudioConfiguration`, `Helper.setAppleAudioConfiguration`,
`Helper.setSpeakerphoneOn`). Пакет `audio_session` удалён намеренно:
он конфликтует с аудио-модулем WebRTC и ломает маршрутизацию.

Настройка идёт **до** `getUserMedia`, `ensureAudioSession()` — **после** него.
До появления аудиотрека плагин считает, что записывать нечего, и Voice
Processing (VPIO на iOS) не включается.
