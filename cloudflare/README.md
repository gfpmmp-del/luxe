# Cloudflare Worker — обход блокировок сети

## Зачем

Приложение ходит только на `jdjgrczsnhroqjasipai.supabase.co`. Часть
мобильных сетей (сотовые операторы, отдельные Wi-Fi, APN) режет или душит
этот домен — без VPN приложение не грузится.

Worker ставится перед Supabase. Клиент общается с обычным доменом
Cloudflare, Worker пересылает запросы дальше. Фильтр по домену
`supabase.co` больше не применяется.

**Что это не даёт:** никакой защиты данных. Ключ anon публичный по
замыслу, доступ ограничивают RLS в базе. Задача воркера — обойти сетевой
фильтр, а не спрятать базу.

## Настройка

### 1. Создать воркер

1. Открой <https://dash.cloudflare.com> → **Workers & Pages**
2. **Create** → **Create Worker**, имя `luxe-proxy`
3. **Deploy**

Открывшийся адрес вида `luxe-proxy.<ник>.workers.dev` — он понадобится
в приложении. Отдельный домен не нужен, `workers.dev` бесплатен.

### 2. Залить код

Worker создан с файлом `index.js`. Замени его содержимое на
`cloudflare/worker.js` из этого репозитория и нажми **Deploy**.

В коде проверь строку:

```js
const UPSTREAM_HOST = 'jdjgrczsnhroqjasipai.supabase.co';
```

### 3. Проверить, что работает

Открой в браузере (на том самом телефоне, где не работает):

```
https://luxe-proxy.<ник>.workers.dev/auth/v1/health
```

Ответ `{}` — значит воркер видит Supabase и всё настроено.
Пустая страница или ошибка — проверь, что адрес воркера верный.

### 4. Включить прокси в приложении

Адрес передаётся при сборке, менять код не нужно:

```cmd
flutter build apk --release --dart-define=SUPABASE_URL=https://luxe-proxy.<ник>.workers.dev
```

Или для Windows:

```cmd
flutter build windows --release --dart-define=SUPABASE_URL=https://luxe-proxy.<ник>.workers.dev
```

Для iOS в `codemagic.yaml` добавь в секцию сборки:

```yaml
    args:
      - --dart-define=SUPABASE_URL=https://luxe-proxy.<ник>.workers.dev
```

Если адрес станет постоянным — впиши его в
`lib/config/supabase_config.dart`, поле `_proxyUrl`, тогда `--dart-define`
не понадобится.

## Статус

Прокси развёрнут и работает: `https://luxe-proxy.gfpmmp.workers.dev`

Адрес **вшит в приложение по умолчанию** (`lib/config/supabase_config.dart`,
`workerUrl`), поэтому `--dart-define` больше не нужен. Ответы Supabase
идут как раньше, меняется только домен в цепочке.

Если Worker когда-нибудь придётся отключить, собери с прямым адресом:

```cmd
flutter build apk --release --dart-define=SUPABASE_URL=https://jdjgrczsnhroqjasipai.supabase.co
```

## Как проверить, что прокси жив

Открой на телефоне **без VPN**:

```
https://luxe-proxy.gfpmmp.workers.dev/auth/v1/health?apikey=sb_publishable_AC4IUfDWKTpiqDForg49ig_KrJ2ZbAp
```

Ответ от GoTrue (сервер авторизации Supabase) — значит цепочка цела.
Ошибка про `apikey` — ключ не подставился, проверь адрес.

## Ограничения, о которых стоит знать

- **Бесплатный план — 100 000 запросов в сутки.** Для мессенджера с
  десятками пользователей хватает; для тысяч — уже нужен платный тариф.
- **`workers.dev` режут реже, но тоже режут.** Если блокируют и его —
  нужен свой домен: добавить воркеру домен в разделе Custom Domains.
- **Данные идут через Cloudflare.** Это ещё один посредник в цепочке.
  Для мессенджера с шифрованием от клиента до клиента это имело бы
  значение; здесь переписка и так шифруется только на участке
  клиент→Supabase.
- **Worker не ускоряет связь** сам по себе. Он добавляет один хоп, зато
  перестаёт упираться в фильтр.

## Откат

Если что-то пошло не так, убери `--dart-define=SUPABASE_URL` и
пересобери: приложение вернётся на прямой адрес Supabase.
