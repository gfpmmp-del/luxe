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

## Сеть: обход блокировок

Часть мобильных сетей режет `*.supabase.co` — без VPN приложение не
грузится. Отдельная правка кода тут не поможет: домен один, и если он
зарезан, клиенту некуда идти.

Решение — Cloudflare Worker перед Supabase (`cloudflare/worker.js`).
Но проверка показала: **прямой адрес работает, а через Worker запросы
доходят до Worker и там завершаются успешно — тело ответа до телефона
не доходит.** Причина в доставке ответа, а не в сети и не в самой базе.

Поэтому сейчас порядок такой:

1. Приложение пробует **прямой** адрес Supabase
2. Не ответил — пробует **Worker** как запасной путь
3. Выбранный маршрут показан в `Настройки → О Luxe`

Строго на прокси принудительно:
```cmd
flutter build apk --release --dart-define=SUPABASE_URL=https://luxe-proxy.<ник>.workers.dev
```

Если Worker придётся чинить — смотреть на доставку ответа клиенту,
а не на проброс заголовков: запросы до Worker доходят, логи это показывают.

## Обновления

Приложение само проверяет `latest.json` в корне репозитория:
`https://raw.githubusercontent.com/gfpmmp-del/luxe/master/latest.json`
Запасной адрес — тот же файл в бакете `chat-media` на случай, если сеть
режет GitHub.

**Перед выпуском новой версии:**
1. Поднять `version` в `pubspec.yaml` и в `latest.json`
2. Собрать с `--dart-define=APP_VERSION=<версия>` — без него приложение
   считает себя `1.0.0` и обновление не предложит
3. Выложить `luxe.apk` и `LuxeMessenger-windows.zip` в Releases GitHub
   с тегом `v<версия>`
4. Обновить ссылки `apk_url` и `zip_url` в `latest.json`
5. `git add -A && git commit && git push`

**Где что невозможно:**
- iOS — приложение не может обновить себя, только TestFlight или App Store
- Android — система всё равно спросит подтверждение установки
- Windows — файлы заняты запущенной программой, подменой занимается
  маленький `.cmd` после выхода из приложения

`AndroidManifest.xml` объявляет `FileProvider`, без него системный
установщик не откроет скачанный APK. Пути — в `res/xml/file_paths.xml`.

## Голосовые: важная деталь

`record` требует **настоящий** путь к файлу. На Android внутри стоит
`MediaRecorder.setOutputFile(path)`, и на пустой строке он выбрасывает
исключение — запись просто не начинается. Путь задаёт сам
`VoiceService` через `getTemporaryDirectory()`.

Отказ по любой причине показывается пользователю. Молчаливый отказ
выглядит как сломанная кнопка, и чинить приходится вслепую.

