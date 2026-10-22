// Sends one queued message (a row of `push_outbox`) to every phone of its
// recipient, through Firebase Cloud Messaging.
//
// Called by the database webhook on `push_outbox` inserts, never by the app.
// Deployed with "Verify JWT" OFF: the webhook proves itself with the
// `x-push-secret` header instead, compared with the PUSH_SECRET secret.
//
// Secrets (Edge Functions → Secrets): PUSH_SECRET, and FCM_SERVICE_ACCOUNT — the
// whole JSON of a Firebase service account key, on one line. SUPABASE_URL and
// SUPABASE_SERVICE_ROLE_KEY are provided by Supabase itself.

import { createClient } from 'npm:@supabase/supabase-js@2'
import { JWT } from 'npm:google-auth-library@9'

const account = JSON.parse(Deno.env.get('FCM_SERVICE_ACCOUNT')!)
const pushSecret = Deno.env.get('PUSH_SECRET')!
const db = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
)

// The notification channel the app creates for these (not built yet: until it
// is, Android files them under its default one, which still shows them).
const CHANNEL_ID = 'group_activity'

async function accessToken(): Promise<string> {
  const client = new JWT({
    email: account.client_email,
    key: account.private_key,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  })
  const { access_token } = await client.authorize()
  return access_token!
}

Deno.serve(async (req) => {
  if (req.headers.get('x-push-secret') !== pushSecret) {
    return new Response('forbidden', { status: 403 })
  }

  const { record } = await req.json()
  const { data: phones, error } = await db
    .from('device_tokens')
    .select('token')
    .eq('user_id', record.user_id)
  if (error) return new Response(error.message, { status: 500 })

  const bearer = await accessToken()
  const data = Object.fromEntries(
    Object.entries(record.data ?? {}).map(([k, v]) => [k, String(v)]),
  )
  let failed = false

  for (const { token } of phones ?? []) {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
      {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${bearer}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title: record.title, body: record.body },
            data,
            // High: a normal message can wait out the phone's sleep (Doze).
            android: {
              priority: 'HIGH',
              notification: { channel_id: CHANNEL_ID },
            },
          },
        }),
      },
    )
    if (res.ok) continue

    // Only "this token no longer exists" drops the token. Any other refusal can
    // be our own mistake, and deleting a good token for it would silence a phone.
    const body = await res.json().catch(() => null)
    const code = body?.error?.details?.find((d: any) => d.errorCode)?.errorCode
    if (code === 'UNREGISTERED') {
      await db.from('device_tokens').delete().eq('token', token)
    } else {
      failed = true
      console.error('FCM refused', res.status, JSON.stringify(body))
    }
  }

  // Kept when something failed, so it can be looked at.
  if (failed) return new Response('some sends failed', { status: 502 })
  await db.from('push_outbox').delete().eq('id', record.id)
  return new Response('ok')
})
