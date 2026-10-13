# Luxe Messenger

Telegram-подобный мессенджер на **Flutter + Supabase + WebRTC**.
Один код → Android, iPhone, Windows.

## Что уже работает
- Регистрация / вход (Supabase Auth)
- Список чатов в стиле Telegram
- Личные чаты 1-на-1 по username + групповой чат
- Realtime-сообщения (без перезагрузки)
- Аудио / видео звонки 1-на-1 (WebRTC, сигналинг через Supabase)

## 1. Установка инструментов (один раз)

1. **Flutter SDK**: https://docs.flutter.dev/get-started/install/windows
   - Распакуй в `C:\flutter`, добавь `C:\flutter\bin` в PATH
   - Проверь: `flutter doctor`
2. **Для Android**: установи Android Studio → SDK + эмулятор
3. **Для Windows**: установи Visual Studio 2022 с workload «Desktop development with C++»
4. **Для iPhone**: нужен Mac с Xcode (на Windows iOS собрать нельзя, но код уже готов)
5. Проект уже создан в папке `luxe/`

```powershell
cd "C:\Users\Admin\Desktop\месенеджер\luxe"
flutter pub get
```

## 2. Бэкенд Supabase (5 минут, бесплатно)

1. Зарегистрируйся на https://supabase.com → New Project
2. Открой **SQL Editor** → вставь содержимое `supabase/schema.sql` → Run
3. **Storage** → New bucket `chat-media` → сделать Public
4. **Project Settings → API** → скопируй `Project URL` и `anon public key`
5. Вставь их в `lib/config/supabase_config.dart`

## 3. Запуск

```powershell
# Windows
flutter run -d windows

# Android (эмулятор или телефон по USB с отладкой)
flutter run -d android

# Посмотреть доступные устройства
flutter devices
```

Для iPhone (только на Mac):
```bash
flutter run -d ios
```

## 4. Как пользоваться

1. Зарегистрируй 2 аккаунта (2 устройства или Windows + телефон)
2. На экране контактов найди второго по username → нажми → создастся чат
3. Пиши сообщения — они приходят мгновенно
4. Трубка вверху чата → аудио/видео звонок. На втором устройстве — входящий звонок с кнопками Принять/Отклонить

## 5. Сборка для установки

```powershell
# Android APK для отправки друзьям
flutter build apk --release
# файл: build\app\outputs\flutter-apk\app-release.apk

# Windows установщик (exe)
flutter build windows --release
# папка: build\windows\x64\runner\Release\

# iOS (на Mac)
flutter build ipa --release
```

## Структура
```
lib/
  main.dart              — вход, инициализация Supabase
  config/supabase_config.dart
  services/auth_service.dart
  services/chat_service.dart
  services/call_service.dart  — WebRTC + Supabase signaling
  screens/auth_screen.dart
  screens/home_screen.dart    — список чатов + контакты + настройки (Telegram UI)
  screens/chat_screen.dart
  screens/call_screen.dart
  widgets/incoming_call.dart
```

## Важно про звонки
- Видео/аудио идут напрямую между устройствами (P2P, WebRTC).
- На разных Wi-Fi / мобильных сетях нужен STUN (уже встроен Google STUN).
- Если оба за строгим NAT — позже добавим TURN-сервер (coturn), сейчас для 90% случаев работает без него.
