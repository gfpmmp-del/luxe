/**
 * Прокси для Luxe Messenger.
 *
 * Зачем: часть мобильных сетей режет домен *.supabase.co — без VPN
 * приложение не может ни войти, ни загрузить переписку. Здесь клиент
 * общается с обычным доменом Cloudflare, а уже Worker пересылает
 * запросы в Supabase.
 *
 * Пути идут как есть: /rest/v1, /auth/v1, /storage/v1 и
 * /realtime/v1/websocket. Поэтому в приложении меняется только
 * базовый URL — больше ничего трогать не нужно.
 *
 * Что это НЕ даёт: никакой защиты данных. Ключ anon и так публичный,
 * а доступ ограничивают правила RLS в самой базе. Задача воркера —
 * обойти сетевой фильтр, а не спрятать базу.
 */

// Проект Supabase. Меняется один раз, здесь и в приложении.
const UPSTREAM_HOST = 'jdjgrczsnhroqjasipai.supabase.co';

// Домен Worker, например luxe-proxy.ivan.workers.dev
// Воркер НЕ должен обращаться сам к себе — иначе получится петля.

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // WebSocket идёт мимо обычного fetch, для него свой маршрут.
    if (isWebSocketUpgrade(request)) {
      return handleWebSocket(request, url);
    }

    const target = `https://${UPSTREAM_HOST}${url.pathname}${url.search}`;
    const headers = forwardHeaders(request);
    // Просим Supabase отдавать ответ без сжатия. Иначе Worker распаковывает
    // тело, а заголовок content-encoding уходит клиенту вместе с уже
    // распакованными байтами — часть клиентов (в том числе dart:io на
    // телефоне) после этого молча зависает в ожидании ответа.
    headers.set('Accept-Encoding', 'identity');

    const started = Date.now();
    try {
      const upstream = await fetch(target, {
        method: request.method,
        headers,
        // Тело отдаём потоком: файлы не копятся в памяти Worker.
        body: request.method === 'GET' || request.method === 'HEAD'
          ? undefined
          : request.body,
        redirect: 'manual',
      });

      // Без этого лога невозможно понять, куда девается запрос
      // приложения: лента пустая, ошибки нет, а чаты не грузятся.
      console.log(
        `${request.method} ${url.pathname}${url.search} -> ` +
        `${upstream.status} за ${Date.now() - started}мс`
      );

      return new Response(upstream.body, {
        status: upstream.status,
        statusText: upstream.statusText,
        headers: forwardResponseHeaders(upstream.headers),
      });
    } catch (e) {
      // Сеть обрезала соединение на полпути. 502 честнее, чем
      // непонятная пустая ошибка на телефоне.
      console.error(
        `${request.method} ${url.pathname} не прошёл за ${Date.now() - started}мс: ${e}`
      );
      return new Response('Прокси не смог связаться с сервером', {
        status: 502,
        headers: { 'content-type': 'text/plain; charset=utf-8' },
      });
    }
  },
};

function isWebSocketUpgrade(request) {
  return request.headers.get('Upgrade')?.toLowerCase() === 'websocket';
}

/**
 * Проксирование WebSocket.
 *
 * Cloudflare умеет держать WebSocket через Worker, но соединение нужно
 * поднять в обе стороны и связать их обработчиками сообщений.
 */
async function handleWebSocket(request, url) {
  const pair = new WebSocketPair();
  const client = pair[0];
  const server = pair[1];

  const target = `wss://${UPSTREAM_HOST}${url.pathname}${url.search}`;

  // Supabase Realtime (Phoenix) требует заголовок протокола,
  // например vsn.1.0.0. Без него сервер откажет соединение.
  const proto = request.headers.get('Sec-WebSocket-Protocol');

  let upstream;
  try {
    upstream = new WebSocket(target, proto ? proto.split(',').map(s => s.trim()) : undefined);
  } catch (e) {
    server.close(1011, 'upstream error');
    return new Response(null, { status: 101, webSocket: client });
  }

  let open = false;

  server.accept();

  upstream.onopen = () => {
    open = true;
  };

  // Сообщения туда
  server.onmessage = (event) => {
    if (open || upstream.readyState === WebSocket.OPEN) {
      upstream.send(event.data);
    }
  };

  // И обратно
  upstream.onmessage = (event) => {
    server.send(event.data);
  };

  const closeBoth = (code, reason) => {
    try {
      if (open) upstream.close(code, reason);
    } catch (_) {}
    try {
      server.close(code, reason);
    } catch (_) {}
  };

  upstream.onclose = (event) => closeBoth(event.code || 1000, 'upstream');
  upstream.onerror = () => closeBoth(1011, 'upstream error');
  server.onclose = () => {
    try {
      if (open) upstream.close(1000, 'client');
    } catch (_) {}
  };
  server.onerror = () => {
    try {
      if (open) upstream.close(1011, 'client error');
    } catch (_) {}
  };

  return new Response(null, { status: 101, webSocket: client });
}

/** Заголовки запроса без того, что задаёт сам Cloudflare. */
function forwardHeaders(request) {
  const headers = new Headers();
  for (const [key, value] of request.headers.entries()) {
    const lower = key.toLowerCase();
    // Host выставляется платформой под целевой адрес, копировать нельзя.
    // Content-Length пересчитается сам.
    if (lower === 'host' || lower === 'content-length') continue;
    headers.set(key, value);
  }
  return headers;
}

/** Заголовки ответа: длину и кодировку задаём сами. */
function forwardResponseHeaders(upstream) {
  const headers = new Headers();
  for (const [key, value] of upstream.entries()) {
    const lower = key.toLowerCase();
    // Кодировку выкидываем: Worker уже распаковал тело, а заголовок
    // остался от исходного ответа.
    if (lower === 'content-encoding' || lower === 'content-length') continue;
    // set-cookie приходит списком — иначе теряются все, кроме первого.
    if (lower === 'set-cookie') continue;
    headers.append(key, value);
  }
  const cookies = upstream.getSetCookie?.() ?? [];
  for (const c of cookies) headers.append('set-cookie', c);
  return headers;
}
