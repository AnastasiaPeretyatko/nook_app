-- The diary, as the server keeps it.
--
-- Run once, in the Supabase dashboard → SQL Editor. Safe to run again: every
-- statement is guarded, because a script pasted into a web editor gets pasted
-- twice sooner or later.
--
-- ## What this mirrors
--
-- The five local tables of `lib/database/tables.dart`. The mapping is not
-- one-to-one, and the differences are the whole design:
--
--   * The local `id` — an autoincrement integer — is **not here**. It counts
--     from 1 on each device, so it means nothing outside the phone that issued
--     it. What travels is the local `uid`, and here it is the primary key.
--
--   * `user_id` is new. Locally there is nobody to belong to; here every row
--     does, and row-level security is the only thing standing between one
--     account's diary and another's.
--
--   * There are two timestamps where the app has one, and `deleted_at` where
--     the app has a tombstone table. Both are explained where they appear.
--
-- ## What is deliberately not here
--
-- Tasks, habits, logs and timer sessions — this is the diary only.
--
-- Pictures. `cover_image` and `images` carry file **names**, and the files
-- themselves stay on the device that made them until the Storage step. A note
-- arriving on a second device will show that it has a cover and be unable to
-- draw it, which is the honest thing for it to do: the name is the truth, the
-- file is merely missing.

-- ---------------------------------------------------------------------------
-- The clock
-- ---------------------------------------------------------------------------

-- Stamps `updated_at` on the server's own clock, on every write.
--
-- Load-bearing. A client pulls with "give me everything changed since X", and
-- if X were measured by the device's clock, then a phone running two minutes
-- fast would skip every row written in those two minutes — silently, and
-- forever. The watermark has to be read from one clock, and this is it.
--
-- The client's own idea of when it edited travels separately, in
-- `client_updated_at`, and that is what conflict resolution compares: which
-- edit came *first* is a question about the two devices, not about the server.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- The notes
-- ---------------------------------------------------------------------------

create table if not exists public.diary_entries (
  -- The local `uid`. Minted on the device that created the note and never
  -- changed, which is what lets two phones agree they are talking about the
  -- same note.
  id uuid primary key,

  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,

  title text not null default '',

  -- The Parchment (Quill) Delta, as JSON text. Text and not jsonb on purpose:
  -- jsonb normalises — it reorders keys and drops insignificant whitespace —
  -- and this column is a document the editor wrote, which should come back
  -- exactly as it went in. Nothing here ever queries inside it.
  body text not null default '',

  -- File names, not paths and not URLs. See the note at the top.
  cover_image text,
  images text not null default '[]',

  is_favorite boolean not null default false,

  -- A check rather than a Postgres enum type: adding a value to an enum is a
  -- migration with a lock, and this list may well grow ("Черновики" is wired
  -- and empty today). The strings are the Dart enum's own names.
  status text not null default 'normal'
    check (status in ('draft', 'normal', 'archived')),

  created_at timestamptz not null default now(),

  -- When the **device** last edited the note. Compared against the other
  -- device's copy to decide whose edit survives.
  client_updated_at timestamptz not null default now(),

  -- When the **server** last saw a write. The pull watermark; never written by
  -- a client.
  updated_at timestamptz not null default now(),

  -- Soft deletion, and here it is the right shape — unlike on the device,
  -- where it would have forced every existing query in the app to filter. A
  -- deletion has to remain visible long enough for the other devices to notice
  -- it, and a row that is simply gone is indistinguishable from one they have
  -- not been sent yet.
  deleted_at timestamptz
);

create table if not exists public.note_moods (
  id uuid primary key,
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  name text not null,
  emoji text not null,
  created_at timestamptz not null default now(),
  client_updated_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.note_tags (
  id uuid primary key,
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  name text not null,
  -- Which family of the app's palette, not the colour itself: `violet`,
  -- `green`, `orange`, `blue`, `pink`, `yellow`, `red`. See
  -- `002_tag_colour_key.sql` for why — in short, an ARGB number is a fact
  -- about one version of one palette, and an opaque one does not even fit
  -- in an `integer`.
  color_key text not null default 'violet',
  created_at timestamptz not null default now(),
  client_updated_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

-- ---------------------------------------------------------------------------
-- The links
-- ---------------------------------------------------------------------------
--
-- No `id`, no timestamps, no `deleted_at` — and that is not an oversight.
--
-- A link has no identity: it *is* the pair of its parents. And it is never
-- pulled on its own. Changing a note's labels marks the note itself as changed
-- (see `DiaryDao.setEntryMoods`), so a device that pulls a note fetches that
-- note's whole set of links with it and replaces what it had — exactly the
-- delete-then-insert the app does locally. There is therefore nothing for a
-- watermark to be compared against, and nothing a tombstone would tell anyone.
--
-- `on delete cascade` here does what the app has to do by hand: locally
-- `PRAGMA foreign_keys` is never enabled, so `DiaryDao.deleteEntry` deletes the
-- link rows itself. Postgres enforces its keys, which also means the push order
-- matters — notes and catalogues before links, always.

create table if not exists public.diary_entry_moods (
  entry_id uuid not null
    references public.diary_entries (id) on delete cascade,
  mood_id uuid not null
    references public.note_moods (id) on delete cascade,
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  primary key (entry_id, mood_id)
);

create table if not exists public.diary_entry_tags (
  entry_id uuid not null
    references public.diary_entries (id) on delete cascade,
  tag_id uuid not null
    references public.note_tags (id) on delete cascade,
  user_id uuid not null default auth.uid()
    references auth.users (id) on delete cascade,
  primary key (entry_id, tag_id)
);

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

drop trigger if exists diary_entries_updated_at on public.diary_entries;
create trigger diary_entries_updated_at
  before insert or update on public.diary_entries
  for each row execute function public.set_updated_at();

drop trigger if exists note_moods_updated_at on public.note_moods;
create trigger note_moods_updated_at
  before insert or update on public.note_moods
  for each row execute function public.set_updated_at();

drop trigger if exists note_tags_updated_at on public.note_tags;
create trigger note_tags_updated_at
  before insert or update on public.note_tags
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
--
-- One shape of query does almost all the reading: "everything of mine changed
-- since X". Both columns, in this order, because the account is an equality
-- and the watermark is a range.

create index if not exists diary_entries_user_updated
  on public.diary_entries (user_id, updated_at);
create index if not exists note_moods_user_updated
  on public.note_moods (user_id, updated_at);
create index if not exists note_tags_user_updated
  on public.note_tags (user_id, updated_at);

-- Links are always fetched by the note they belong to.
create index if not exists diary_entry_moods_entry
  on public.diary_entry_moods (entry_id);
create index if not exists diary_entry_tags_entry
  on public.diary_entry_tags (entry_id);

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
--
-- The only thing protecting the data. The key shipped inside the app is
-- publishable by design — Supabase's own documentation says to put it in the
-- source — so what keeps one account out of another's diary is these policies
-- and nothing else. A table left without them is readable by anyone holding
-- the key, which is everyone who has the APK.
--
-- `using` governs which existing rows a statement may see or touch; `with
-- check` governs what a row is allowed to look like after being written. Insert
-- needs the second: without it a client could write somebody else's `user_id`.
--
-- Three details below follow Supabase's own performance guidance for policies:
--
--   * `auth.uid()` is wrapped as `(select auth.uid())`. That turns it into an
--     initPlan the planner evaluates **once per statement** instead of once per
--     row — the same answer, a fraction of the calls.
--   * Every policy names its role with `to authenticated`, so the check stops
--     there for anyone else instead of evaluating the condition first.
--   * `user_id` is indexed (above). A policy filters every candidate row, and
--     an unindexed filter column turns each read into a sequential scan.

alter table public.diary_entries enable row level security;
alter table public.note_moods enable row level security;
alter table public.note_tags enable row level security;
alter table public.diary_entry_moods enable row level security;
alter table public.diary_entry_tags enable row level security;

do $$
declare
  t text;
begin
  foreach t in array array[
    'diary_entries',
    'note_moods',
    'note_tags',
    'diary_entry_moods',
    'diary_entry_tags'
  ]
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
-- unauthenticated client sees nothing at all. That is deliberate — the diary
-- has no public half.
