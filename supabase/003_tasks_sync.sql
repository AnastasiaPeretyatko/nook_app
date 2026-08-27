-- Tasks, habits and their day marks, as the server keeps them.
--
-- Run once, in the Supabase dashboard → SQL Editor. Safe to run again: every
-- statement is guarded, because a script pasted into a web editor gets pasted
-- twice sooner or later.
--
-- ## The frame
--
-- Supabase here is a **backup against losing the phone**, not a shared desk. It
-- follows directly that a moment-to-moment state does not travel: a running
-- timer is one device's live state and has no meaning on another.
--
-- ## Two tables, where the diary needed five
--
--   * `task_sessions` is **not here**. `ended_at` and `duration_seconds` are
--     write-only columns — `_closeRun` fills them and nothing reads them — and
--     every lasting trace of a run is folded into that day's log before the
--     session is closed. Restore `task_logs` and every screen in the app draws
--     exactly what it drew.
--
--   * `events` is not here either. The table and its DAO exist; no screen uses
--     them.
--
--   * There are no link tables and no catalogues: a task refers to nothing but
--     its own parent.
--
-- ## And one `uid` where the diary needed three
--
-- `task_logs` has **no** synthetic identity. Its identity is the pair
-- `(task_id, date)` — the task and the calendar day — and that is the primary
-- key. This is not a saving, it is the design: with random uuids, two phones
-- that ticked today's habit independently would arrive with two rows for one day
-- and something would have to merge them. With a natural key they converge on
-- their own, with no merge logic anywhere.
--
-- For the same reason the logs need no `deleted_at`. Nothing in the app deletes
-- a single mark — the one statement that deletes any deletes every mark of one
-- task — so a mark's disappearance is always already told by its task's.

-- ---------------------------------------------------------------------------
-- The tasks
-- ---------------------------------------------------------------------------

create table if not exists public.tasks (
  -- The local `uid`, minted on the device that created the task and never
  -- changed. The local `id` is an autoincrement integer that counts from 1 on
  -- every device, so it means nothing outside the phone that issued it.
  id uuid primary key,

  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,

  -- A subtask points at its parent, in the same table. `on delete cascade` is
  -- for the account being deleted; an ordinary deletion is a `deleted_at` and
  -- never reaches it — see the blanking trigger below.
  --
  -- It is also why the push order matters: Postgres checks a foreign key row by
  -- row, so a child sent ahead of its parent is refused outright. `SyncService`
  -- sends the batch in generations.
  parent_id uuid references public.tasks (id) on delete cascade,

  title text not null default '',
  description text,

  -- Checks rather than Postgres enum types: adding a value to an enum is a
  -- migration with a lock, and these lists can grow. The strings are the Dart
  -- enums' own names.
  status text not null default 'active'
    check (status in ('active', 'paused', 'archived')),

  -- Null means a one-off task rather than a habit, which is the difference
  -- between the two tabs of the app. Not a missing value.
  repeat_type text
    check (repeat_type is null
           or repeat_type in ('daily', 'weekly', 'monthly', 'custom')),
  repeat_interval integer,

  -- A bitmask: day `d` sets bit `d - 1`. Weekly counts `DateTime.weekday`
  -- (1–7), monthly the day of the month (1–31), so it stays well inside int4.
  repeat_days_mask integer,

  tracking_mode text not null default 'checkbox'
    check (tracking_mode in ('checkbox', 'counter', 'timer', 'value')),
  target_duration_minutes integer,

  -- Both the counter's and the free-value mode's target. `double precision`
  -- because the local column is a Dart `double`.
  target_value double precision,

  -- A key into the app's icon catalogue, never a font code point: a code point
  -- means something only inside one version of one font, which is why migration
  -- v10 stopped storing one.
  icon_key text,

  -- Which family of the app's palette — `violet`, `green`, `orange`, `blue`,
  -- `pink`, `yellow`, `red` — and **not** the colour itself, for the reason
  -- `002_tag_colour_key.sql` spells out for tags: an ARGB number is a fact about
  -- one version of one palette, and an opaque one begins with `0xFF`, putting it
  -- above 2^31 where a Postgres `integer` refuses it outright. SQLite takes such
  -- a value without comment, so the mismatch exists only at this boundary.
  --
  -- Nullable, unlike a tag's: a task with no colour is a real state, drawn in
  -- the first family, and it has to survive the round trip as itself.
  color_key text,

  -- Minutes from midnight. Null start means the task sits on the untimed strip.
  scheduled_time_minutes integer,
  end_time_minutes integer,

  -- A **calendar day**, not a moment, hence `date` and not `timestamptz`.
  -- Locally it is midnight *in the device's own zone*, so sent as an instant it
  -- would come back a day earlier for everyone east of Greenwich — silently, and
  -- only for some users. The client spells it `YYYY-MM-DD` and rebuilds local
  -- midnight on the way back.
  start_date date,

  created_at timestamptz not null default now(),

  -- When the **device** last edited the task. Compared against the other
  -- device's copy to decide whose edit survives.
  client_updated_at timestamptz not null default now(),

  -- When the **server** last saw a write. The pull watermark; never written by
  -- a client.
  updated_at timestamptz not null default now(),

  -- Soft deletion. A deletion has to stay visible long enough for the other
  -- devices to notice it: a row that is simply gone is indistinguishable from
  -- one they have not been sent yet, so without this the task would come
  -- straight back on the next pull.
  deleted_at timestamptz
);

-- ---------------------------------------------------------------------------
-- The day marks
-- ---------------------------------------------------------------------------

create table if not exists public.task_logs (
  task_id uuid not null
    references public.tasks (id) on delete cascade,

  -- The calendar day, for the same reason `tasks.start_date` is a `date`.
  date date not null,

  completed boolean not null default false,

  -- A counter's count or a timer's banked seconds, depending on the task's
  -- tracking mode. One column because a day has one answer.
  value double precision,

  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,

  client_updated_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- The pair **is** the row, and saying so here is what makes two devices
  -- converge: an upsert resolving on this key updates the day rather than
  -- duplicating it. No `id` column exists to conflict on instead.
  --
  -- Note for the day shared tasks arrive: this would have to become
  -- `(task_id, user_id, date)`, because each participant ticks a shared task
  -- separately. Worth settling before this ships, or it is two migrations.
  primary key (task_id, date)
);

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------
--
-- `public.set_updated_at()` comes from `001_diary_sync.sql`; it stamps the
-- server's own clock on every write, which is what the pull watermark is read
-- from. A watermark measured by a device's clock would make a phone running two
-- minutes fast skip every row written in those two minutes — silently, and
-- forever.

drop trigger if exists tasks_updated_at on public.tasks;
create trigger tasks_updated_at
  before insert or update on public.tasks
  for each row execute function public.set_updated_at();

drop trigger if exists task_logs_updated_at on public.task_logs;
create trigger task_logs_updated_at
  before insert or update on public.task_logs
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Emptying what was deleted
-- ---------------------------------------------------------------------------
--
-- A deleted task keeps its row forever and loses its contents at once. The row
-- that stays is `id`, `user_id` and `deleted_at` — some fifty bytes.
--
-- ## Why this rather than deleting the row after N days
--
-- A retention window has to be longer than the longest silence of *any* device,
-- and there is no such number. A tablet nobody opened for longer than the window
-- asks "what changed since?", is told nothing — the row it needed is gone — and
-- keeps the task, clean. Edit it there and it goes back up: the task the user
-- deleted returns to the phone. Nothing errs, nothing logs, and it is close to
-- impossible to reproduce afterwards. Keeping the row forever means the
-- deletion can always still be told, so that failure simply cannot happen.
--
-- ## Why the logs need deleting explicitly
--
-- `on delete cascade` above never fires for an ordinary deletion, because an
-- ordinary deletion is an `update ... set deleted_at` and the row is never
-- actually removed. The cascade is there for the account going away. So the
-- marks — of which an active habit has far more than there are tasks — are
-- deleted here, by hand, and they go **immediately** rather than in three
-- months.
--
-- ## Why it fires on every update of a deleted row, not just the first
--
-- A device that has not heard about the deletion may push the task again. Its
-- upsert names the data columns and not `deleted_at`, so the row stays deleted,
-- the trigger blanks it once more, and the marks go again. That is the same rule
-- the client's own merge follows: a deletion wins outright, without consulting
-- the clocks. The device's edit is lost, which is the deliberate trade — losing
-- an edit is a mistake the user can see and redo, while a task that will not
-- stay deleted is one they cannot fix.
create or replace function public.blank_deleted_task()
returns trigger
language plpgsql
as $$
begin
  new.parent_id := null;
  new.title := '';
  new.description := null;
  new.status := 'active';
  new.repeat_type := null;
  new.repeat_interval := null;
  new.repeat_days_mask := null;
  new.tracking_mode := 'checkbox';
  new.target_duration_minutes := null;
  new.target_value := null;
  new.icon_key := null;
  new.color_key := null;
  new.scheduled_time_minutes := null;
  new.end_time_minutes := null;
  new.start_date := null;

  delete from public.task_logs where task_id = new.id;

  return new;
end;
$$;

drop trigger if exists tasks_blank_when_deleted on public.tasks;
create trigger tasks_blank_when_deleted
  before update on public.tasks
  for each row
  when (new.deleted_at is not null)
  execute function public.blank_deleted_task();

-- A mark for a task that is already deleted is dropped rather than stored.
--
-- Without this the emptying above has a hole: the task's row still *exists*, so
-- the foreign key is satisfied, and a device that has not heard about the
-- deletion can put its marks back — where nothing would ever clear them again.
--
-- `return null` in a `before insert` row trigger skips that row and raises
-- nothing. Silently, on purpose: an error would fail the whole push and block
-- everything queued behind it, and the client loses nothing by being kept in the
-- dark — it drops those marks itself the moment it learns the task is gone.
create or replace function public.skip_log_of_deleted_task()
returns trigger
language plpgsql
as $$
begin
  if exists (
    select 1 from public.tasks
    where id = new.task_id and deleted_at is not null
  ) then
    return null;
  end if;
  return new;
end;
$$;

drop trigger if exists task_logs_skip_deleted on public.task_logs;
create trigger task_logs_skip_deleted
  before insert or update on public.task_logs
  for each row execute function public.skip_log_of_deleted_task();

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
--
-- One shape of query does almost all the reading: "everything of mine changed
-- since X". Both columns, in this order, because the account is an equality and
-- the watermark is a range. `user_id` being indexed also matters to the policies
-- below — a policy filters every candidate row, and an unindexed filter column
-- turns each read into a sequential scan.

create index if not exists tasks_user_updated
  on public.tasks (user_id, updated_at);
create index if not exists task_logs_user_updated
  on public.task_logs (user_id, updated_at);

-- The self-reference. Postgres indexes the primary key of a foreign key but not
-- the referencing column, and both the cascade and the blanking trigger look
-- rows up by it.
create index if not exists tasks_parent
  on public.tasks (parent_id);

-- `task_logs (task_id)` needs no index of its own: it is the leading column of
-- the primary key, so that index already answers "the marks of this task".

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
--
-- The only thing protecting the data. The key shipped inside the app is
-- publishable by design, so what keeps one account out of another's is these
-- policies and nothing else. A table left without them is readable by anyone
-- holding the key, which is everyone who has the APK.
--
-- Same three details as `001_diary_sync.sql`, all from Supabase's own guidance:
-- `auth.uid()` wrapped as `(select auth.uid())` so the planner evaluates it once
-- per statement rather than once per row; every policy naming its role with
-- `to authenticated`; and `user_id` indexed above.
--
-- `task_logs` carries its own `user_id` rather than being checked through its
-- task. It costs a uuid per row and buys a policy that is a plain equality on an
-- indexed column, where the alternative is an `exists` subquery on every row
-- read, written or deleted.

alter table public.tasks enable row level security;
alter table public.task_logs enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array['tasks', 'task_logs']
  loop
    execute format('drop policy if exists %I on public.%I', t || '_select', t);
    execute format('drop policy if exists %I on public.%I', t || '_insert', t);
    execute format('drop policy if exists %I on public.%I', t || '_update', t);
    execute format('drop policy if exists %I on public.%I', t || '_delete', t);

    execute format(
      'create policy %I on public.%I for select to authenticated
         using ((select auth.uid()) = user_id)', t || '_select', t);
    execute format(
      'create policy %I on public.%I for insert to authenticated
         with check ((select auth.uid()) = user_id)', t || '_insert', t);
    execute format(
      'create policy %I on public.%I for update to authenticated
         using ((select auth.uid()) = user_id)
         with check ((select auth.uid()) = user_id)', t || '_update', t);
    execute format(
      'create policy %I on public.%I for delete to authenticated
         using ((select auth.uid()) = user_id)', t || '_delete', t);
  end loop;
end;
$$;

-- Signed out is not "read everything": no policy is granted to `anon`, so an
-- unauthenticated client sees nothing at all.
