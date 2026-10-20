-- The eight seeded moods stop belonging to anybody.
--
-- Run once, in the Supabase dashboard → SQL Editor, and safe to run again like
-- the three before it.
--
-- ## The bug this fixes
--
-- `defaultNoteMoods` (lib/utils/note_labels.dart) gives the eight moods the app
-- ships with **fixed uuids, written out in the source**. That is right, and the
-- reason is spelled out there: the seeding runs once per device, so a phone and
-- a tablet would otherwise mint sixteen rows for the same eight feelings.
--
-- But `note_moods.id` was a primary key over the whole table, so those eight
-- uuids existed **once for every user in the database**, not once per user. The
-- first account ever to sync claimed them; every account after it opened its
-- first push with an upsert of ids that were taken, and Postgres answered the
-- only way it can — a duplicate key, or, on the ON CONFLICT path, a row the
-- update policy will not show it. Either way the statement raised.
--
-- Moods are pushed **first**, ahead of tags, notes, links and tasks, so the
-- whole run died there. The account ended up with a user row and not one row of
-- anything else, and nothing the user could do — reinstalling, toggling the
-- switch, editing their tasks — changed it, because the eight uuids are
-- compiled into the app.
--
-- ## The fix, and why it is this one
--
-- A seeded mood is not the user's data. It is a constant of the app: it lives
-- in Dart, it arrives with the install, and nothing in the app can rename or
-- delete it — `DiaryDao` has `insertMood` and no update or delete at all. What
-- travels between devices is the **link** ("this note is marked Радость"), and
-- a link carries the fixed uuid, which every device already understands without
-- the row ever having been sent.
--
-- So the row exists here for exactly one reason: `diary_entry_moods.mood_id`
-- has a foreign key into this table and Postgres enforces it. One shared row
-- per mood satisfies that for everybody.
--
-- `user_id is null` is what "belongs to the application" is spelled as. The
-- select policy is widened to let those rows through; insert, update and delete
-- are left exactly as they were, and since `null = auth.uid()` is null rather
-- than true, that alone makes a shared mood unwritable by anyone. The rule the
-- app enforced by having no button for it is now enforced by the database.
--
-- **This widening belongs to `note_moods` and nowhere else.** Every other table
-- here is one person's data, and a policy that lets nulls through would be a
-- hole rather than a catalogue.
--
-- ## What it costs
--
-- Eight rows for the whole installation instead of eight per user, and eight
-- fewer rows on every account's first sync. If a later version ever wants to
-- let someone rename their own "Грусть", this becomes a shared catalogue with
-- per-user overrides on top — a real change, and not one today's app asks for.

-- ---------------------------------------------------------------------------
-- 1. Ownership becomes optional
-- ---------------------------------------------------------------------------
--
-- Guarded, because a second run would otherwise fail on a column that is
-- already nullable — and this file is pasted into a web editor, which is to say
-- it will be pasted twice.

do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public'
      and table_name = 'note_moods'
      and column_name = 'user_id'
      and is_nullable = 'NO'
  ) then
    alter table public.note_moods alter column user_id drop not null;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. The select policy lets the shared rows through
-- ---------------------------------------------------------------------------
--
-- Only this one. `note_moods_insert`, `_update` and `_delete` keep the plain
-- equality from `001_diary_sync.sql`, which is what makes the eight rows
-- read-only for every client: `null = auth.uid()` is null, never true.
--
-- `(select auth.uid())` for the same reason as everywhere else in 001 — the
-- planner evaluates it once per statement instead of once per row.

drop policy if exists note_moods_select on public.note_moods;
create policy note_moods_select on public.note_moods
  for select to authenticated
  using ((select auth.uid()) = user_id or user_id is null);

-- ---------------------------------------------------------------------------
-- 3. The eight rows, owned by nobody
-- ---------------------------------------------------------------------------
--
-- `on conflict do nothing` covers the fresh database. The update below covers
-- the one that already has them under the first account that ever synced: the
-- contents are already right — they are a constant — and only the owner is
-- wrong. Their `id` does not change, so every link already pointing at them
-- stays valid.
--
-- The uuids, names and emoji must stay identical to `defaultNoteMoods` in
-- lib/utils/note_labels.dart. Changing one on either side makes it a different
-- mood to every device that already seeded the old one.

insert into public.note_moods (id, user_id, name, emoji) values
  ('0f8a4c3e-1d92-4b7a-9c15-6e2f8a01b4d3', null, 'Радость',       '😊'),
  ('2b6d91f7-84ca-4e35-b0d8-77c4e9a12f56', null, 'Спокойствие',   '🌿'),
  ('5c31e0a8-2f47-4d69-8b3e-91da6c25f087', null, 'Размышления',   '🤔'),
  ('7e94b2d1-6a08-4c52-9f7b-38e5c1470ab9', null, 'Грусть',        '😢'),
  ('9a07f3c5-4b81-4e20-a6d9-52fb8c364e1a', null, 'Усталость',     '😴'),
  ('b3d85e19-7c62-4a0f-8e41-6db29f057c34', null, 'Благодарность', '🙏'),
  ('d51c7a26-9e34-4f8b-b273-40a6e8d91cf5', null, 'Тревога',       '😰'),
  ('f28b60d4-3a15-4c97-9e56-18c7b2f4a06e', null, 'Любовь',        '❤️')
on conflict (id) do nothing;

update public.note_moods set user_id = null
where user_id is not null
  and id in (
    '0f8a4c3e-1d92-4b7a-9c15-6e2f8a01b4d3',
    '2b6d91f7-84ca-4e35-b0d8-77c4e9a12f56',
    '5c31e0a8-2f47-4d69-8b3e-91da6c25f087',
    '7e94b2d1-6a08-4c52-9f7b-38e5c1470ab9',
    '9a07f3c5-4b81-4e20-a6d9-52fb8c364e1a',
    'b3d85e19-7c62-4a0f-8e41-6db29f057c34',
    'd51c7a26-9e34-4f8b-b273-40a6e8d91cf5',
    'f28b60d4-3a15-4c97-9e56-18c7b2f4a06e'
  );

-- ---------------------------------------------------------------------------
-- 4. Check it
-- ---------------------------------------------------------------------------
--
--   select id, name, user_id from public.note_moods order by name;
--
-- Eight rows with a null `user_id`, plus whatever moods the users invented.
