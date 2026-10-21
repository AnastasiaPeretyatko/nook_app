-- Push: which phones belong to whom.
--
-- Run once, in the Supabase dashboard → SQL Editor, after `010_realtime_profiles.sql`.
-- Safe to run again.
--
-- Nothing sends a push yet; running it early does no harm. This only gives the
-- app a place to say "this phone is mine, send my notifications here".
--
-- ## One row per phone, not per account
--
-- The key is the FCM token, which names a *device*. A person with two phones has
-- two rows; two people who sign in on one phone in turn have one row that moves
-- from one to the other. The last to sign in owns it, because the token reaches
-- whoever holds the phone.
--
-- ## Why functions and no policies
--
-- The table has RLS on and **no policies**, so a client cannot read or write it
-- directly. A plain "owner only" policy would break the hand-over above: the
-- second account cannot update a row the first one owns. The two functions below
-- check the caller themselves, like the group functions of `005_groups.sql`.
-- The server side of push (Edge Function, service role) reads the table past RLS.

create table if not exists public.device_tokens (
  token text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  updated_at timestamptz not null default now()
);

create index if not exists device_tokens_user_id_idx
  on public.device_tokens (user_id);

alter table public.device_tokens enable row level security;

-- Takes the token over for the caller, wherever it was before.
create or replace function public.register_device(p_token text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if p_token is null or length(p_token) not between 20 and 4096 then
    raise exception 'bad_token';
  end if;
  insert into public.device_tokens (token, user_id)
  values (p_token, auth.uid())
  on conflict (token)
  do update set user_id = auth.uid(), updated_at = now();
end;
$$;

-- Only the owner can drop a token: someone else's phone is not theirs to remove.
create or replace function public.unregister_device(p_token text)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  delete from public.device_tokens
   where token = p_token and user_id = auth.uid();
end;
$$;

revoke execute on function public.register_device(text) from public, anon;
revoke execute on function public.unregister_device(text) from public, anon;
grant execute on function public.register_device(text) to authenticated;
grant execute on function public.unregister_device(text) to authenticated;

-- To check, signed in as a user (the dashboard's SQL editor runs as postgres,
-- where auth.uid() is null): select public.register_device('x' || repeat('a', 30));
-- and then, as the service role: select * from public.device_tokens;
