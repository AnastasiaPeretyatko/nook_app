-- Realtime for member names.
--
-- A member publishes their name (`profiles`) on their own first sync after
-- joining a group — which can land a moment after the group owner's phone has
-- already synced on the `group_members` event. Without an event on `profiles`
-- the owner keeps seeing "Участник" until the next scheduled sync.
--
-- Safe to run twice. Events still respect RLS: a phone hears only about the
-- profiles it may read (its own and its group mates').

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'profiles'
  ) then
    alter publication supabase_realtime add table public.profiles;
  end if;
end $$;
