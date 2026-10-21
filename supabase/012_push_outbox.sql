-- Push: the queue of messages waiting to be sent.
--
-- Run once, in the Supabase dashboard → SQL Editor, after `011_device_tokens.sql`.
-- Safe to run again.
--
-- A row here means "tell this person this". The Edge Function `push`
-- (`supabase/functions/push/index.ts`) finds the person's phones in
-- `device_tokens`, sends the message through FCM and deletes the row. A row that
-- is still here has not been delivered — the function leaves it when FCM failed
-- for a reason other than a dead token, so it can be looked at.
--
-- Nothing fills it yet: the triggers that do (a task made, a task done) come in
-- a later file. Until then a row can be inserted by hand to try the whole chain
-- with no second person and no group.
--
-- ## No policies
--
-- RLS is on and there are no policies, so no client can read or write the queue:
-- one person's notifications must never be something another can plant. Only the
-- server (triggers, the service role) touches it.
--
-- ## The webhook (dashboard → Database → Webhooks, not SQL)
--
-- The call to the function carries a secret, and a secret does not belong in a
-- file that is committed — so this one is made by hand:
--
--   * Name: push_outbox_insert
--   * Table: public.push_outbox, event: Insert
--   * Type: Supabase Edge Functions → `push`, method POST, timeout 5000
--   * HTTP header: `x-push-secret` = the same value as the function's
--     `PUSH_SECRET` secret

create table if not exists public.push_outbox (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  title text not null,
  body text not null default '',
  -- Strings only: FCM carries nothing else. Read by the app on a tap.
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.push_outbox enable row level security;

-- To try it, in the SQL editor (the token must be one in device_tokens):
--   insert into public.push_outbox (user_id, title, body)
--   select user_id, 'Проверка', 'Это пробное уведомление'
--   from public.device_tokens limit 1;
