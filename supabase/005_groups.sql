-- Groups: shared one-off tasks between accounts.
--
-- Run once, in the Supabase dashboard → SQL Editor, after `003_tasks_sync.sql`.
-- Safe to run again, like the files before it.
--
-- **Ship it together with the app version that knows about groups.** Step 4
-- changes the key of `task_logs`, and an older app pushes its marks with
-- `on conflict (task_id, date)` — which Postgres refuses once no unique index
-- has exactly those columns. Every sync of that older app fails until it is
-- updated.
--
-- ## The frame changes
--
-- `003_tasks_sync.sql` opens with "a backup against losing the phone, not a
-- shared desk". For tasks with a `group_id` that is no longer true: other
-- accounts read them, and their owner and author edit them. Personal tasks keep
-- every rule they had.
--
-- ## The rules this file enforces
--
--   * A group task is a **one-off task without subtasks** (`repeat_type`,
--     `parent_id` null, not the "Значение" mode). Habits in groups are not part
--     of this version.
--   * `tasks.user_id` is the **author** — the client never sends it, the
--     default stamps the writer, and a trigger keeps it from changing after.
--   * Only the group's **owner** and the task's **author** edit or delete it.
--   * `assignee_id` null means "for everyone": one shared task, closed for all
--     by the first member's tick. Each member still writes only their own mark
--     (which is why a mark is keyed by its user too); the phones read "done" as
--     "any member's mark is ticked", so the server needs no rule for it.
--   * A task's group is fixed at creation. Moving a task out of a group would
--     leave a copy on every other member's phone forever: the row stops being
--     visible to them, and an invisible row is indistinguishable from one that
--     did not change.
--
-- ## Groups are written through functions, never directly
--
-- Creating, joining, leaving, removing, renaming and deleting are each several
-- writes that have to land together (a group needs its owner's membership and
-- an invite code; leaving unassigns the leaver's tasks), and joining has to
-- reach a group the caller cannot see yet. So the three group tables have
-- select policies only, and every change goes through a `security definer`
-- function below that checks the caller itself. These need the network — group
-- management is not queued for sync like a task edit is.
--
-- ## How a phone learns it is out
--
-- A membership is never deleted, only stamped `deleted_at`, and a member can
-- always read their own membership rows. That stamp is the one signal a phone
-- gets for "removed", "left on another device" and "the group was deleted" —
-- once it lands, everything of that group comes off the device. Without it the
-- tasks would simply stop arriving, which looks exactly like nothing changing.

-- ---------------------------------------------------------------------------
-- 1. Tables
-- ---------------------------------------------------------------------------

-- The name and picture other members see. Written by the client from its own
-- session metadata; `auth.users` itself is not readable by a client.
create table if not exists public.profiles (
  user_id uuid primary key default auth.uid()
    references auth.users (id) on delete cascade,
  display_name text,
  avatar_url text,
  updated_at timestamptz not null default now()
);

create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(name) between 1 and 100),
  owner_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- The owner has a row here too, with `role = 'owner'`: "who is in the group" is
-- then one table and one question.
create table if not exists public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (group_id, user_id)
);

-- Its own table, not a column of `groups`: a policy decides which rows are
-- visible, never which columns, and the code is the owner's alone to see.
create table if not exists public.group_invites (
  group_id uuid primary key references public.groups (id) on delete cascade,
  code text not null unique,
  updated_at timestamptz not null default now()
);

alter table public.tasks
  add column if not exists group_id uuid
    references public.groups (id) on delete cascade;
alter table public.tasks
  add column if not exists assignee_id uuid
    references auth.users (id) on delete set null;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'tasks_group_task_shape'
  ) then
    alter table public.tasks add constraint tasks_group_task_shape check (
      group_id is null
      or (repeat_type is null and parent_id is null
          and tracking_mode <> 'value')
    );
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'tasks_assignee_needs_group'
  ) then
    alter table public.tasks add constraint tasks_assignee_needs_group
      check (assignee_id is null or group_id is not null);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Who is who — helpers for the policies
-- ---------------------------------------------------------------------------
--
-- `security definer`: they read `group_members` past its own policy. A policy
-- on `group_members` that queried `group_members` directly would recurse, and
-- Postgres refuses that with "infinite recursion detected in policy".
-- `search_path = ''` so a definer function cannot be steered to someone else's
-- table of the same name; every name in them is schema-qualified.

create or replace function public.is_group_member(g uuid, u uuid default auth.uid())
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.group_members m
    where m.group_id = g and m.user_id = u and m.deleted_at is null
  );
$$;

create or replace function public.is_group_owner(g uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.groups gr
    where gr.id = g and gr.owner_id = auth.uid() and gr.deleted_at is null
  );
$$;

-- Whether the caller and `u` are in a group together. The caller's side must
-- be current; `u`'s may be over — a member who left still authored tasks the
-- others are looking at, and those should keep their name.
create or replace function public.shares_group_with(u uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1
    from public.group_members me
    join public.group_members them on them.group_id = me.group_id
    where me.user_id = auth.uid() and me.deleted_at is null
      and them.user_id = u
  );
$$;

-- Whether `u` may put a mark on the task. Null when the task is not on the
-- server at all, so the caller can tell "refused" from "unknown".
create or replace function public.can_mark_task(t uuid, u uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select case
    when tk.group_id is null then tk.user_id = u
    else public.is_group_member(tk.group_id, u)
         and (tk.assignee_id is null or tk.assignee_id = u)
  end
  from public.tasks tk
  where tk.id = t;
$$;

-- ---------------------------------------------------------------------------
-- 3. Triggers
-- ---------------------------------------------------------------------------

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at
  before insert or update on public.profiles
  for each row execute function public.set_updated_at();

drop trigger if exists groups_updated_at on public.groups;
create trigger groups_updated_at
  before insert or update on public.groups
  for each row execute function public.set_updated_at();

drop trigger if exists group_members_updated_at on public.group_members;
create trigger group_members_updated_at
  before insert or update on public.group_members
  for each row execute function public.set_updated_at();

-- What the client may not change, and an assignee who is not a member.
--
-- Silently corrected rather than refused: a refusal fails the whole push and
-- blocks everything queued behind it. The assignee case is ordinary, not
-- hostile — a phone offline while someone was removed can push a task still
-- naming them.
create or replace function public.guard_group_task()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' then
    new.user_id := old.user_id;
    new.group_id := old.group_id;
  end if;
  if new.assignee_id is not null
     and (new.group_id is null
          or not public.is_group_member(new.group_id, new.assignee_id)) then
    new.assignee_id := null;
  end if;
  return new;
end;
$$;

drop trigger if exists tasks_guard_group on public.tasks;
create trigger tasks_guard_group
  before insert or update on public.tasks
  for each row execute function public.guard_group_task();

-- The blanking trigger of 003 deletes a deleted task's marks. Run as the caller
-- it would only see — and so only delete — the caller's own, leaving every
-- other member's marks behind. As the definer it deletes them all.
alter function public.blank_deleted_task() security definer;
alter function public.blank_deleted_task() set search_path = public;

-- Replaces 003's version. Still drops a mark of a deleted task, and now also a
-- mark its user may not make: not a member any more, or the task was handed to
-- someone else while this phone was offline. Silent for the reason in 003 — an
-- error would block the push. A task the server has never heard of is let
-- through, so the foreign key refuses it loudly as before.
create or replace function public.skip_log_of_deleted_task()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if exists (
    select 1 from public.tasks
    where id = new.task_id and deleted_at is not null
  ) then
    return null;
  end if;
  if public.can_mark_task(new.task_id, new.user_id) is false then
    return null;
  end if;
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. A mark belongs to a person
-- ---------------------------------------------------------------------------
--
-- The change `003_tasks_sync.sql` foresaw: everyone ticks a "for everyone" task
-- for themselves, so one task has one mark per member per day. Every existing
-- row already carries its `user_id`, so the wider key cannot collide.
--
-- The client still never names `user_id`; the default fills it before the
-- conflict is resolved, so `on conflict (task_id, user_id, date)` works.

alter table public.task_logs drop constraint if exists task_logs_pkey;
alter table public.task_logs
  add constraint task_logs_pkey primary key (task_id, user_id, date);

-- ---------------------------------------------------------------------------
-- 5. Indexes
-- ---------------------------------------------------------------------------

create index if not exists tasks_group on public.tasks (group_id);
-- `shares_group_with` looks memberships up by user; the primary key leads with
-- the group.
create index if not exists group_members_user on public.group_members (user_id);

-- ---------------------------------------------------------------------------
-- 6. Row-level security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.group_invites enable row level security;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using ((select auth.uid()) = user_id or public.shares_group_with(user_id));
drop policy if exists profiles_insert on public.profiles;
create policy profiles_insert on public.profiles for insert to authenticated
  with check ((select auth.uid()) = user_id);
drop policy if exists profiles_update on public.profiles;
create policy profiles_update on public.profiles for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

-- Select only: every write is one of the functions in step 7.
drop policy if exists groups_select on public.groups;
create policy groups_select on public.groups for select to authenticated
  using (public.is_group_member(id));

-- Your own rows always, removed ones included — that is the "you are out"
-- signal. Everyone's rows of a group you are in.
drop policy if exists group_members_select on public.group_members;
create policy group_members_select on public.group_members
  for select to authenticated
  using ((select auth.uid()) = user_id or public.is_group_member(group_id));

drop policy if exists group_invites_select on public.group_invites;
create policy group_invites_select on public.group_invites
  for select to authenticated
  using (public.is_group_owner(group_id));

-- Tasks. Personal rows: 003's equality. Group rows: any member reads; a member
-- creates; the author or the owner edits. Every group clause asks for current
-- membership, the author's included — someone removed keeps no hold on, and no
-- view of, what they wrote there.
drop policy if exists tasks_select on public.tasks;
create policy tasks_select on public.tasks for select to authenticated
  using (
    (group_id is null and (select auth.uid()) = user_id)
    or (group_id is not null and public.is_group_member(group_id))
  );

drop policy if exists tasks_insert on public.tasks;
create policy tasks_insert on public.tasks for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and (group_id is null or public.is_group_member(group_id))
  );

drop policy if exists tasks_update on public.tasks;
create policy tasks_update on public.tasks for update to authenticated
  using (
    (group_id is null and (select auth.uid()) = user_id)
    or (group_id is not null and public.is_group_member(group_id)
        and ((select auth.uid()) = user_id or public.is_group_owner(group_id)))
  )
  with check (
    (group_id is null and (select auth.uid()) = user_id)
    or (group_id is not null and public.is_group_member(group_id)
        and ((select auth.uid()) = user_id or public.is_group_owner(group_id)))
  );

drop policy if exists tasks_delete on public.tasks;
create policy tasks_delete on public.tasks for delete to authenticated
  using (
    (group_id is null and (select auth.uid()) = user_id)
    or (group_id is not null and public.is_group_member(group_id)
        and ((select auth.uid()) = user_id or public.is_group_owner(group_id)))
  );

-- Marks. Everyone in the group sees everyone's marks of a group task (that is
-- the "2 из 3"); each writes only their own, and only where they may.
drop policy if exists task_logs_select on public.task_logs;
create policy task_logs_select on public.task_logs for select to authenticated
  using (
    (select auth.uid()) = user_id
    or exists (
      select 1 from public.tasks tk
      where tk.id = task_id and tk.group_id is not null
        and public.is_group_member(tk.group_id)
    )
  );

drop policy if exists task_logs_insert on public.task_logs;
create policy task_logs_insert on public.task_logs for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    and public.can_mark_task(task_id, user_id)
  );

drop policy if exists task_logs_update on public.task_logs;
create policy task_logs_update on public.task_logs for update to authenticated
  using ((select auth.uid()) = user_id)
  with check (
    (select auth.uid()) = user_id
    and public.can_mark_task(task_id, user_id)
  );

-- `task_logs_delete` stays as 003 made it: your own marks.

-- ---------------------------------------------------------------------------
-- 7. The functions groups are changed through
-- ---------------------------------------------------------------------------
--
-- Each checks the caller itself — `security definer` skips every policy above.
-- Errors are raised with a fixed message the client maps to Russian text:
-- `not_signed_in`, `bad_name`, `bad_code`, `not_owner`, `owner_cannot_leave`.

-- 8 characters from 31 that cannot be misread for one another (no 0/O, 1/I/L):
-- 31^8 ≈ 8.5·10^11 codes, far past guessing. The bytes come from
-- `gen_random_uuid`, which is cryptographically random; `random()` is not.
create or replace function public.new_invite_code()
returns text
language plpgsql volatile set search_path = ''
as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  bytes bytea;
  v_code text;
begin
  loop
    bytes := uuid_send(gen_random_uuid());
    v_code := '';
    for i in 0..7 loop
      v_code := v_code || substr(alphabet, get_byte(bytes, i) % 31 + 1, 1);
    end loop;
    exit when not exists (select 1 from public.group_invites i where i.code = v_code);
  end loop;
  return v_code;
end;
$$;

create or replace function public.create_group(p_name text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  clean text := btrim(coalesce(p_name, ''));
  g uuid;
begin
  if me is null then raise exception 'not_signed_in'; end if;
  if length(clean) not between 1 and 100 then raise exception 'bad_name'; end if;

  insert into public.groups (name, owner_id) values (clean, me) returning id into g;
  insert into public.group_members (group_id, user_id, role) values (g, me, 'owner');
  insert into public.group_invites (group_id, code) values (g, public.new_invite_code());
  return g;
end;
$$;

create or replace function public.rename_group(p_group uuid, p_name text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  clean text := btrim(coalesce(p_name, ''));
begin
  if not public.is_group_owner(p_group) then raise exception 'not_owner'; end if;
  if length(clean) not between 1 and 100 then raise exception 'bad_name'; end if;
  update public.groups set name = clean where id = p_group;
end;
$$;

create or replace function public.regenerate_invite(p_group uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
  v_code text := public.new_invite_code();
begin
  if not public.is_group_owner(p_group) then raise exception 'not_owner'; end if;
  update public.group_invites set code = v_code, updated_at = now()
   where group_id = p_group;
  return v_code;
end;
$$;

-- Joining. Also re-joining: a membership that was stamped over is revived.
--
-- Then everything of the group is touched. The phone pulls "changed since my
-- last sync", and the group's tasks were written before that moment — without
-- the touch the new member would receive the tasks written from now on and
-- never the ones already there. Touching costs every other member one
-- re-download of rows identical to theirs, which the client overwrites without
-- a visible change.
create or replace function public.join_group(p_code text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  clean text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  g uuid;
begin
  if me is null then raise exception 'not_signed_in'; end if;

  select i.group_id into g
  from public.group_invites i
  join public.groups gr on gr.id = i.group_id
  where i.code = clean and gr.deleted_at is null;
  if g is null then raise exception 'bad_code'; end if;

  if public.is_group_member(g, me) then return g; end if;

  insert into public.group_members (group_id, user_id, role)
  values (g, me, 'member')
  on conflict (group_id, user_id)
    do update set deleted_at = null, joined_at = now();

  update public.group_members set updated_at = now() where group_id = g;
  update public.tasks set updated_at = now() where group_id = g;
  update public.task_logs set updated_at = now()
   where task_id in (select id from public.tasks where group_id = g);
  return g;
end;
$$;

-- What leaving and being removed have in common. The tasks handed to the
-- member go back to "nobody yet" for the owner to hand out again; their
-- `client_updated_at` moves too, or a phone holding an older unsent edit would
-- win the merge and assign them straight back.
create or replace function public.drop_member(p_group uuid, p_user uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  update public.group_members set deleted_at = now()
   where group_id = p_group and user_id = p_user and deleted_at is null;
  update public.tasks set assignee_id = null, client_updated_at = now()
   where group_id = p_group and assignee_id = p_user;
end;
$$;

create or replace function public.leave_group(p_group uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if auth.uid() is null then raise exception 'not_signed_in'; end if;
  if public.is_group_owner(p_group) then raise exception 'owner_cannot_leave'; end if;
  perform public.drop_member(p_group, auth.uid());
end;
$$;

create or replace function public.remove_member(p_group uuid, p_user uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_group_owner(p_group) then raise exception 'not_owner'; end if;
  if p_user = auth.uid() then raise exception 'owner_cannot_leave'; end if;
  perform public.drop_member(p_group, p_user);
end;
$$;

-- The group, its memberships and its tasks are all stamped deleted; the
-- blanking trigger of 003 empties the tasks and removes their marks. The rows
-- stay, for the reason 003 gives for tasks: a deletion has to stay visible to a
-- phone that was offline when it happened.
create or replace function public.delete_group(p_group uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not public.is_group_owner(p_group) then raise exception 'not_owner'; end if;
  update public.groups set deleted_at = now() where id = p_group;
  update public.group_members set deleted_at = now()
   where group_id = p_group and deleted_at is null;
  update public.tasks set deleted_at = now(), client_updated_at = now()
   where group_id = p_group and deleted_at is null;
end;
$$;

-- Postgres lets everyone run a new function by default, `anon` included. The
-- functions check `auth.uid()` anyway; this keeps the door shut as well.
-- `drop_member` and `new_invite_code` are internal: no client may call them.
do $$
declare
  f text;
begin
  foreach f in array array[
    'is_group_member(uuid, uuid)', 'is_group_owner(uuid)',
    'shares_group_with(uuid)', 'can_mark_task(uuid, uuid)',
    'create_group(text)', 'rename_group(uuid, text)',
    'regenerate_invite(uuid)', 'join_group(text)', 'leave_group(uuid)',
    'remove_member(uuid, uuid)', 'delete_group(uuid)',
    'drop_member(uuid, uuid)', 'new_invite_code()'
  ]
  loop
    execute format('revoke execute on function public.%s from public, anon', f);
  end loop;
  foreach f in array array[
    'is_group_member(uuid, uuid)', 'is_group_owner(uuid)',
    'shares_group_with(uuid)', 'can_mark_task(uuid, uuid)',
    'create_group(text)', 'rename_group(uuid, text)',
    'regenerate_invite(uuid)', 'join_group(text)', 'leave_group(uuid)',
    'remove_member(uuid, uuid)', 'delete_group(uuid)'
  ]
  loop
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
  revoke execute on function public.drop_member(uuid, uuid) from authenticated;
  revoke execute on function public.new_invite_code() from authenticated;
end;
$$;
