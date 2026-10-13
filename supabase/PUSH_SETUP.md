# Push-уведомления (Android / iOS)

Реализовано через Firebase Cloud Messaging. Токены устройств хранятся в
таблице `push_tokens`, отправка — через Supabase Edge Function, которую
вызывает триггер на вставку в `messages`.

## Что где лежит

| Файл | Назначение |
|---|---|
| `lib/services/push_service.dart` | Инициализация Firebase, запрос прав, сохранение токена, показ уведомления в foreground |
| `lib/services/auth_service.dart` | Вызывает `PushService.init()` после входа и регистрации |
| `supabase/add_push.sql` | Таблица `push_tokens` + RLS |
| `supabase/add_push_trigger.sql` | Триггер: новое сообщение → вызов Edge Function |
| `supabase/functions/send-push/index.ts` | Edge Function: рассылает FCM по токенам получателей |
| `android/app/google-services.json` | **PLACEHOLDER** — заменить своим |
| `third_party/firebase_core/` | Локальная копия firebase_core **без** `windows/` |

## Почему `third_party/firebase_core`

`firebase_core` для Windows скачивает Firebase C++ SDK — это ~806 МБ zip
и ~4 ГБ после распаковки. При этом FCM на Windows всё равно не поддерживается
(`firebase_messaging` не имеет Windows-реализации).

Поэтому в `pubspec.yaml` есть:

```yaml
dependency_overrides:
  firebase_core:
    path: third_party/firebase_core
```

Локальная копия — это firebase_core без секции `windows:` в pubspec.
Android/iOS/macOS работают как обычно, Windows просто не подключает Firebase
и собирается без 4 ГБ SDK. Удаление `dependency_overrides` вернёт
поведение по умолчанию (и потребует места на диске).

## Настройка Firebase (один раз)

1. https://console.firebase.google.com → Create project
2. Add app → **Android** → package name `com.luxe.luxe`
   - Скачай `google-services.json`
   - **Замени** `android/app/google-services.json` (сейчас там placeholder)
3. Project Settings → Service Accounts → Generate new private key (JSON)
   - Из него возьми `private_key` — это `FCM_SERVER_KEY` для Edge Function
4. iOS (если нужен): Add app → iOS → скачай `GoogleService-Info.plist`
   → положи в `ios/Runner/`

## Настройка Supabase (один раз)

1. SQL Editor → выполни `supabase/add_push.sql`
2. SQL Editor → выполни `supabase/add_push_trigger.sql`
3. Edge Functions → создай `send-push`, вставь код из
   `supabase/functions/send-push/index.ts`
4. Secrets → добавь:
   ```
   FCM_SERVER_KEY = "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
   ```

## Как это работает

```
Пользователь пишет сообщение
        ↓
INSERT в messages
        ↓
триггер on_message_created
        ↓
Edge Function send-push
        ↓
находит токены всех участников чата (кроме отправителя) в push_tokens
        ↓
FCM → телефон
        ↓
приложение открыто?  → onMessage → локальное уведомление
приложение закрыто? → системное уведомление Android
```

Токен сохраняется в `push_tokens` при каждом входе (`AuthService.signIn`)
и обновляется на `onTokenRefresh`.

## Проверка

Установи APK на два устройства, войди разными аккаунтами. На одном оставь
приложение закрытым, с другого отправь сообщение — первое получит push.

Если в логах `flutter run` видишь `Push: permission=..., token=null`,
значит токен не получен: проверь, что `google-services.json` заменён на настоящий.

## Известные ограничения

- **Windows не получает push** — FCM там не работает (см. выше)
- Уведомление о **звонке** пока не отправляется — только сообщения
- `PushService.init()` обёрнут в try/catch: без Firebase приложение
  работает, просто без уведомлений