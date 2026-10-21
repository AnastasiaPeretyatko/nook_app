-- Realtime for groups: the server tells the phones that something changed.
--
-- Run once, in the Supabase dashboard → SQL Editor, after `008_cycle_sync.sql`.
-- Safe to run again.
--
-- Nothing in the app reads this yet; running it early does no harm. It only
-- puts three tables on the `supabase_realtime` list, which is what makes the
-- server send "a row of this table changed" to every phone subscribed to it.
--
-- ## What the phones do with it
--
-- Nothing clever: the event is a doorbell, not data. The app ignores the row it
-- carries and runs its ordinary sync, so the merge rules stay in one place.
--
-- ## Who hears what
--
-- Realtime checks each event against the subscriber's own select policy, so a
-- member hears only about rows they may read anyway (`005_groups.sql`). Nothing
-- here widens who can see what.
--
-- ## Why these three
--
--   * `tasks` — a task was created, edited or deleted. A deletion is a
--     `deleted_at`, i.e. an update, so no `DELETE` event (which Realtime does
--     not check against policies) is ever needed.
--   * `task_logs` — someone ticked a task: "done for everyone" reaches the other
--     members through this.
--   * `group_members` — someone joined, left or was removed.
--
-- `replica identity full` is not needed: the old values of a row are never read.

do $$
declare
  t text;
begin
  foreach t in array array['tasks', 'task_logs', 'group_members'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- To check: should list the three tables.
--   select tablename from pg_publication_tables
--   where pubname = 'supabase_realtime' and schemaname = 'public';
