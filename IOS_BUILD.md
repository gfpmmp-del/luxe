# Сборка iOS без Mac

## Почему нельзя собрать на Windows

Apple требует Xcode, а Xcode существует только для macOS. Никакого легального способа
собрать `.ipa` на Windows нет — только в облаке на чужом Mac.

## Бесплатные варианты

| Сервис | Бесплатно | Сложность |
|---|---|---|
| **Codemagic** | 500 минут macOS-сборок в месяц | Просто, через браузер |
| GitHub Actions | Публичный репозиторий — без ограничений | Нужно знать YAML |
| Bitrise | Есть бесплатный тариф | Средне |

Рекомендую **Codemagic**: без регистрации карты, есть 500 бесплатных минут.

---

## Способ 1: Codemagic (рекомендуется)

### Шаг 1. Залей проект в репозиторий

Нужен GitHub, GitLab или Bitbucket. Проще всего GitHub:

```cmd
cd C:\luxe
git init
git add .
git commit -m "Luxe Messenger"
```

Затем создай пустой репозиторий на https://github.com/new и выполни:

```cmd
git remote add origin https://github.com/ТВОЙ_НИК/luxe.git
git branch -M main
git push -u origin main
```

> ⚠️ Перед `git add .` проверь, что в проекте нет секретов. Файл
> `android/app/google-services.json` содержит ключ Firebase — он попадёт в
> репозиторий. Для мессенджера на GitHub это некритично (ключ ограничен
> пакетом приложения), но лучше добавь в `.gitignore`:
> ```
> android/app/google-services.json
> supabase/functions/
> *.jks
> *.keystore
> ```
> Тогда загрузи ключ вручную в Codemagic через **codemagic.yaml** или
> через переменные окружения.

### Шаг 2. Зарегистрируйся на Codemagic

1. Открой https://codemagic.io/signup (через GitHub — вход в один клик)
2. **Add application** → выбери свой репозиторий с Luxe
3. Открой **Configuration** → **Flutter build**
4. Codemagic создаст файл конфигурации — замени его содержимое на `codemagic.yaml`
   из корня проекта (или вставь вручную)
5. Нажми **Start new build** → выбери `ios-unsigned`

### Шаг 3. Забери файл

Сборка идёт 10–20 минут. Готовый `.ipa` лежит в **Artifacts** рядом с логом.

---

## Способ 2: GitHub Actions

Создай в корне репозитория файл `.github/workflows/ios.yml`:

```yaml
name: Build iOS
on:
  workflow_dispatch:

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.27.0'
          channel: stable
      - run: flutter pub get
      - run: flutter build ios --debug --no-codesign
      - name: Package IPA
        run: |
          cd build/ios/iphoneos
          mkdir -p Payload
          cp -R Runner.app Payload/
          zip -qry luxe.ipa Payload
      - uses: actions/upload-artifact@v4
        with:
          name: luxe-ios
          path: build/ios/iphoneos/luxe.ipa
```

Запуск: **Actions → Build iOS → Run workflow**.
Файл скачается в **Artifacts** внизу страницы запуска.

---

## Установка на iPhone

### Вариант A — без Apple Developer Account (бесплатно)

Нужен компьютер (Windows подойдёт) и:

1. Скачай **Sideloadly**: https://sideloadly.io
   (или AltStore: https://altstore.io)
2. Подключи iPhone по USB, в настройках телефона включи **Режим разработчика**
3. В Sideloadly выбери свой `.ipa` и свой Apple ID
4. Приложение установится

⚠️ **Ограничение**: бесплатный Apple ID подписывает приложение на **7 дней**.
Потом нужно переустановить заново (или использовать AltStore — он
переподписывает автоматически, пока компьютер включён с интернетом).

### Вариант B — с Apple Developer Account (99 $/год)

1. Зарегистрируйся на https://developer.apple.com
2. Создай App ID с bundle id `com.luxe.luxe`
3. Создай сертификат и provision profile
4. В Codemagic: **Team → App Store Connect → Automatic code signing**
5. Запусти workflow `ios-signed`

Приложение установится навсегда, можно раздавать другим через TestFlight.

---

## Что ещё не настроено для iOS

### Push-уведомления

Firebase настроен только для Android. Для iOS нужен свой файл:

1. https://console.firebase.google.com → проект **gfpmmp-f1d95**
2. **Add app → iOS** → Bundle ID укажи `com.luxe.luxe`
3. Скачай `GoogleService-Info.plist`
4. Положи в `ios/Runner/GoogleService-Info.plist`

Без этого push на iOS не заработает, но само приложение соберётся.

### Проверено

- `Info.plist`: добавлены `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`,
  `NSPhotoLibraryUsageDescription` — без них iOS закрывает приложение при первом звонке
- Добавлен `UIBackgroundModes: audio, voip` — звонки не рвутся при сворачивании
- `IPHONEOS_DEPLOYMENT_TARGET = 15.0` — актуальная версия
- Иконка приложения `app_icon_1024.png` уже сгенерирована