-- A tag stores which colour it is, not what that colour looks like.
--
-- Run once, in the dashboard → SQL Editor, after `001_diary_sync.sql`.
-- Safe to run again: guarded on the old column still being there.
--
-- ## What went wrong first
--
-- `note_tags.color_value` held an ARGB32 number — what `Color.toARGB32()`
-- returns. It is **unsigned** 32-bit, so an opaque colour begins with `0xFF`
-- and lands above 2^31: the default violet `0xFF8B7CF6` is 4287331574.
-- Postgres `integer` is signed int4 and stops at 2147483647, so the first push
-- of a tag was refused outright:
--
--     value "4287331574" is out of range for type integer (22003)
--
-- SQLite had hidden it. Its integers are 64-bit, so the local database took the
-- value without comment, and the mismatch existed only at the boundary between
-- the two — which no amount of Dart testing would have found.
--
-- ## Why the fix is not `bigint`
--
-- Widening the column would have worked and would have been wrong. A number
-- like `0xFF8B7CF6` is a fact about **one version of one palette**: nudge a
-- shade in the app and every tag already written keeps the old one, on every
-- device, until somebody writes a migration to repaint them all.
--
-- So the column holds the palette **key** instead — `violet`, `green`,
-- `orange`, `blue`, `pink`, `yellow`, `red` — and the app resolves it to a
-- colour as it draws. The design can be repainted freely, the database never
-- notices, and the range problem stops existing rather than being accommodated.
--
-- The same move the task icons made locally at schema v10, when they stopped
-- storing a Material code point — meaningful only inside one font — and started
-- storing a key into a catalogue.
--
-- ## Why this drops rather than converts
--
-- Nothing is lost: the push that would have written these rows is the one that
-- failed, so `note_tags` is empty. A `using` clause mapping numbers back to
-- keys would be code written for a case that cannot occur.

do $$
begin
  if exists (
    select 1 from information_schema.columns
     where table_schema = 'public'
       and table_name = 'note_tags'
       and column_name = 'color_value'
  ) then
    alter table public.note_tags drop column color_value;
  end if;
end;
$$;

alter table public.note_tags
  add column if not exists color_key text not null default 'violet';
