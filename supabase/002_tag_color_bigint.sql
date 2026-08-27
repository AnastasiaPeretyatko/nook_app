-- A tag's colour does not fit in an `integer`.
--
-- Run once, in the dashboard → SQL Editor. Safe to run again: widening a column
-- to the type it already has is a no-op.
--
-- ## What went wrong
--
-- `note_tags.color_value` holds an ARGB32 colour — the same value a task stores,
-- the one `Color.toARGB32()` returns. It is **unsigned** 32-bit, so an opaque
-- colour begins with `0xFF` and lands above 2^31: the default violet
-- `0xFF8B7CF6` is 4287331574.
--
-- Postgres `integer` is int4 and **signed**, topping out at 2147483647. Every
-- push of a tag was therefore refused outright:
--
--     value "4287331574" is out of range for type integer (22003)
--
-- SQLite hid it. Its integers are 64-bit, so the local database took the value
-- without comment and the mismatch only existed at the boundary between the
-- two — which is exactly the kind of thing no amount of Dart testing finds.
--
-- `bigint` holds the whole unsigned 32-bit range with room to spare, and the
-- value round-trips exactly rather than being wrapped into a negative.

alter table public.note_tags
  alter column color_value type bigint;
