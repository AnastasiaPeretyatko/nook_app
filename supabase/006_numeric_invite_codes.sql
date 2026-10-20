-- Invite codes become six digits, and guessing them is limited.
--
-- Run once, in the Supabase dashboard → SQL Editor, after `005_groups.sql`.
-- Safe to run again.
--
-- ## Why the limit comes with the shorter code
--
-- Six digits is 10^6 codes, against 005's 31^8 ≈ 8.5·10^11. Short enough to
-- dictate, and short enough to enumerate: unthrottled, a script walks the whole
-- space in hours, and with many groups alive it lands in *some* group after a
-- few hundred tries. So `join_group` now refuses an account that got the code
-- wrong ten times in the last hour — 240 guesses a day, ~11 years for one
-- group's code.
--
-- A wrong code therefore **returns null instead of raising**: a raise rolls the
-- function back, the failed attempt with it, and nothing would ever be counted.
-- The client reads null as "the code did not fit".

-- ---------------------------------------------------------------------------
-- 1. Six digits
-- ---------------------------------------------------------------------------

-- Bytes of a random uuid, keeping only those under 250 so each digit is
-- equally likely (256 is not a multiple of 10). A uuid's 16 bytes almost always
-- hold six such; the outer loop covers the rare one that does not.
create or replace function public.new_invite_code()
returns text
language plpgsql volatile set search_path = ''
as $$
declare
  bytes bytea;
  v_code text;
  b int;
begin
  loop
    v_code := '';
    while length(v_code) < 6 loop
      bytes := uuid_send(gen_random_uuid());
      for i in 0..15 loop
        b := get_byte(bytes, i);
        if b < 250 and length(v_code) < 6 then
          v_code := v_code || (b % 10)::text;
        end if;
      end loop;
    end loop;
    exit when not exists (select 1 from public.group_invites i where i.code = v_code);
  end loop;
  return v_code;
end;
$$;

-- The codes 005 handed out are letters; nobody has been given one that matters
-- yet, so every group gets a fresh numeric one. One row at a time, so each new
-- code is checked against the ones already replaced.
do $$
declare
  g uuid;
begin
  for g in select group_id from public.group_invites where code !~ '^[0-9]{6}$'
  loop
    update public.group_invites
       set code = public.new_invite_code(), updated_at = now()
     where group_id = g;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Counting wrong guesses
-- ---------------------------------------------------------------------------

-- Written and read only by `join_group`; no policy, so no client sees it.
create table if not exists public.group_join_failures (
  user_id uuid not null references auth.users (id) on delete cascade,
  at timestamptz not null default now()
);
create index if not exists group_join_failures_user_at
  on public.group_join_failures (user_id, at);
alter table public.group_join_failures enable row level security;

-- ---------------------------------------------------------------------------
-- 3. Joining, throttled
-- ---------------------------------------------------------------------------

create or replace function public.join_group(p_code text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  clean text := regexp_replace(coalesce(p_code, ''), '[^0-9]', '', 'g');
  g uuid;
begin
  if me is null then raise exception 'not_signed_in'; end if;

  -- Checked before the code, so a right guess past the limit is refused too —
  -- otherwise the limit would only slow down the wrong ones.
  if (select count(*) from public.group_join_failures f
       where f.user_id = me and f.at > now() - interval '1 hour') >= 10 then
    raise exception 'too_many_attempts';
  end if;

  select i.group_id into g
  from public.group_invites i
  join public.groups gr on gr.id = i.group_id
  where i.code = clean and gr.deleted_at is null;

  if g is null then
    delete from public.group_join_failures
     where user_id = me and at < now() - interval '1 day';
    insert into public.group_join_failures (user_id) values (me);
    return null;
  end if;

  if public.is_group_member(g, me) then return g; end if;

  insert into public.group_members (group_id, user_id, role)
  values (g, me, 'member')
  on conflict (group_id, user_id)
    do update set deleted_at = null, joined_at = now();

  -- See 005: the new member pulls "changed since", and these were written
  -- before that.
  update public.group_members set updated_at = now() where group_id = g;
  update public.tasks set updated_at = now() where group_id = g;
  update public.task_logs set updated_at = now()
   where task_id in (select id from public.tasks where group_id = g);
  return g;
end;
$$;

revoke execute on function public.new_invite_code() from public, anon, authenticated;
revoke execute on function public.join_group(text) from public, anon;
grant execute on function public.join_group(text) to authenticated;
