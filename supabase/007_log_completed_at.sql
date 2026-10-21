-- When a day mark was ticked.
--
-- Run once, in the Supabase dashboard → SQL Editor, after
-- `006_numeric_invite_codes.sql`. Safe to run again.
--
-- `date` stays the calendar day — it is part of the key `(task_id, user_id,
-- date)` — so the moment of the tick needs a column of its own. Null on every
-- row ticked before this existed, and on a row that is not ticked.
--
-- Run this BEFORE shipping the app that sends `completed_at`: a push naming a
-- column the table does not have is refused whole, and every sync fails until
-- the column exists. No rows are lost in the meantime — they stay marked unsent
-- on the device — but nothing goes up.
--
-- Additive and nullable, so the running app and older copies of it are
-- unaffected: they neither send nor read the column.

alter table public.task_logs
  add column if not exists completed_at timestamptz;
