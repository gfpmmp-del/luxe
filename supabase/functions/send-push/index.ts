// Supabase Edge Function: send-push (FCM HTTP v1)
//
// Нужен Secret: FCM_SERVICE_ACCOUNT = полный JSON сервис-аккаунта Firebase
// (тот же файл, что скачивается из Firebase Console → Service Accounts).
//
// Вызов: POST /functions/v1/send-push
//   { "user_ids": ["uuid1"], "title": "Иван", "body": "Привет!", "chat_id": "uuid" }

import { createClient } from 'jsr:@supabase/supabase-js@2'

const SCOPE = 'https://www.googleapis.com/auth/firebase.messaging'

/** Подписать JWT (RS256) и обменять на access_token. */
async function getAccessToken(sa: any): Promise<string> {
  const header = btoa(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const now = Math.floor(Date.now() / 1000)
  const claim = btoa(
    JSON.stringify({
      iss: sa.client_email,
      scope: SCOPE,
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  )
  const toBase64Url = (bytes: Uint8Array) =>
    btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')

  const pem = sa.private_key.replace(/\\n/g, '\n')
  const der = Uint8Array.from(
    atob(pem.replace(/-----BEGIN [^-]+-----/g, '').replace(/-----END [^-]+-----/g, '').replace(/\s/g, '')),
    (c) => c.charCodeAt(0),
  )

  const key = await crypto.subtle.importKey(
    'pkcs8',
    der as unknown as BufferSource,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(`${header}.${claim}`) as unknown as BufferSource,
  )

  const jwt = `${header}.${claim}.${toBase64Url(new Uint8Array(sig))}`

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })
  const json = await res.json()
  if (!json.access_token) throw new Error(`oauth failed: ${JSON.stringify(json)}`)
  return json.access_token as string
}

Deno.serve(async (req) => {
  try {
    const raw = Deno.env.get('FCM_SERVICE_ACCOUNT')
    if (!raw) {
      return new Response(JSON.stringify({ error: 'FCM_SERVICE_ACCOUNT not set' }), { status: 500 })
    }
    const sa = JSON.parse(raw)
    const token = await getAccessToken(sa)

    const { user_ids, title, body, chat_id } = await req.json()
    if (!user_ids?.length) {
      return new Response(JSON.stringify({ error: 'user_ids required' }), { status: 400 })
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data: tokens, error } = await supabase
      .from('push_tokens')
      .select('token')
      .in('user_id', user_ids)

    if (error) {
      return new Response(JSON.stringify({ error: error.message }), { status: 500 })
    }

    const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`
    let sent = 0
    const failures: string[] = []

    for (const row of tokens ?? []) {
      const res = await fetch(url, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token: row.token,
            notification: { title, body },
            data: { chat_id: chat_id ?? '', type: 'message' },
            android: { priority: 'HIGH', notification: { channel_id: 'luxe_messages' } },
          },
        }),
      })
      if (res.ok) {
        sent++
      } else {
        failures.push((await res.text()).slice(0, 300))
      }
    }

    return new Response(JSON.stringify({ sent, total: tokens?.length ?? 0, failures }), {
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 })
  }
})