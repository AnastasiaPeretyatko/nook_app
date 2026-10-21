-- The women's calendar: one row per account per day.
--
-- Run once, in the Supabase dashboard → SQL Editor, after
-- `007_log_completed_at.sql`. Safe to run again.
--
-- Run this BEFORE anyone switches on "Синхронизировать цикл": a push to a table
-- that does not exist is refused whole, and every sync fails until it does. The
-- switch is off by default and nothing is lost meanwhile — the days stay marked
-- as unsent on the device.
--
-- ## The key
--
-- `(user_id, date)` is the row, the same bargain `task_logs` strikes: two phones
-- that marked the same day converge with nothing to merge, and there is no `id`.
-- Nothing is ever deleted either — taking a mark back saves the day empty — so
-- there is no `deleted_at` and no tombstone.
--
-- ## Who can see it
--
-- Only the account that wrote it. This is health data: no policy names a group
-- or a member, and none is ever to be added. The four policies below are plain
-- equalities on `user_id`, the same shape as every other table here.
--
-- ## The options
--
-- Small integers, indexes into the lists in `lib/utils/cycle_marks.dart`. The
-- checks bound the *current* lists; a new option is an `alter` of the check, not
-- a new column.

create table if not exists public.cycle_days (
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  date date not null,

  flow smallint not null default 0 check (flow between 0 and 4),
  mood smallint check (mood between 0 and 5),
  symptoms smallint[] not null default '{}'
    check (symptoms <@ array[0,1,2,3,4,5,6,7,8]::smallint[]),
  discharge smallint check (discharge between 0 and 6),
  sex smallint check (sex between 0 and 2),
  pill boolean not null default false,
  note text,

  client_updated_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  primary key (user_id, date)
);

-- `public.set_updated_at()` comes from `001_diary_sync.sql`.
drop trigger if exists cycle_days_updated_at on public.cycle_days;
create trigger cycle_days_updated_at
  before insert or update on public.cycle_days
  for each row execute function public.set_updated_at();

-- "Everything of mine changed since X" is the one query that reads this table.
create index if not exists cycle_days_user_updated
  on public.cycle_days (user_id, updated_at);

alter table public.cycle_days enable row level security;

drop policy if exists cycle_days_select on public.cycle_days;
drop policy if exists cycle_days_insert on public.cycle_days;
drop policy if exists cycle_days_update on public.cycle_days;
drop policy if exists cycle_days_delete on public.cycle_days;

create policy cycle_days_select on public.cycle_days for select to authenticated
  using ((select auth.uid()) = user_id);
create policy cycle_days_insert on public.cycle_days for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy cycle_days_update on public.cycle_days for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy cycle_days_delete on public.cycle_days for delete to authenticated
  using ((select auth.uid()) = user_id);
