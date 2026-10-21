-- Push: who is told what, and when.
--
-- Run once, in the Supabase dashboard → SQL Editor, after `012_push_outbox.sql`
-- (and after the `push` function and its webhook work — try the manual insert
-- at the end of 012 first).
-- Safe to run again.
--
-- Two triggers put rows into `push_outbox`; the webhook and the Edge Function
-- do the rest. These are the same rules the app's toasts follow
-- (`lib/utils/group_events.dart`), written a second time because a closed app
-- cannot apply them. **If one changes, change both.**
--
--   * A task made by someone else is news when it is for me or for everyone.
--     The author is never told about their own task. A task older than an hour
--     is the backlog, not news.
--   * A task handed to me later (its assignee changed to me) is news too.
--   * A mark by someone else is news when the task is for everyone, or when I
--     handed it out myself. The one who ticked is never told.
--
-- The text has no past-tense verb ("Выполнено: Миша"), because a member's gender
-- is unknown. Group tasks are one-off tasks without subtasks (`005_groups.sql`),
-- so there is no habit or subtask to rule out beyond `parent_id`.
--
-- Both functions run as their owner (`security definer`): they read members and
-- write the queue, which the person who made the change may not.

create or replace function public.push_member_name(u uuid)
returns text
language sql stable security definer set search_path = ''
as $$
  select coalesce(
    (select nullif(btrim(p.display_name), '')
       from public.profiles p where p.user_id = u),
    'Участник'
  );
$$;

-- A group task was made, or handed to someone new.
create or replace function public.push_on_task_change()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  gname text;
  who text;
begin
  if new.group_id is null or new.parent_id is not null
     or new.deleted_at is not null or new.status <> 'active' then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.created_at < now() - interval '1 hour' then return new; end if;
  elsif new.assignee_id is null
        or new.assignee_id is not distinct from old.assignee_id then
    -- An edit, or "for everyone" again: nobody new to tell.
    return new;
  end if;

  select g.name into gname
    from public.groups g where g.id = new.group_id and g.deleted_at is null;
  if not found then return new; end if;

  who := public.push_member_name(new.user_id);
  insert into public.push_outbox (user_id, title, body, data)
  select m.user_id,
         case when new.assignee_id is null
              then 'Новая задача для всех от ' || who
              else 'Новая задача от ' || who end,
         new.title || ' · ' || gname,
         jsonb_build_object('group_id', new.group_id, 'task_id', new.id)
    from public.group_members m
   where m.group_id = new.group_id and m.deleted_at is null
     and m.user_id <> new.user_id
     and (new.assignee_id is null or new.assignee_id = m.user_id);
  return new;
end;
$$;

-- A member ticked a group task.
create or replace function public.push_on_task_done()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  t record;
  gname text;
begin
  if not new.completed then return new; end if;
  -- A re-sent mark that was already ticked is not a new tick.
  if tg_op = 'UPDATE' and old.completed then return new; end if;

  select tk.title, tk.group_id, tk.user_id as author, tk.assignee_id
    into t
    from public.tasks tk
   where tk.id = new.task_id and tk.group_id is not null
     and tk.deleted_at is null;
  if not found then return new; end if;

  select g.name into gname
    from public.groups g where g.id = t.group_id and g.deleted_at is null;
  if not found then return new; end if;

  insert into public.push_outbox (user_id, title, body, data)
  select m.user_id,
         'Выполнено: ' || public.push_member_name(new.user_id),
         t.title || ' · ' || gname,
         jsonb_build_object('group_id', t.group_id, 'task_id', new.task_id)
    from public.group_members m
   where m.group_id = t.group_id and m.deleted_at is null
     and m.user_id <> new.user_id
     -- For everyone: all the others. Handed to someone: only whoever handed it.
     and (t.assignee_id is null or m.user_id = t.author);
  return new;
end;
$$;

drop trigger if exists tasks_push on public.tasks;
create trigger tasks_push
  after insert or update of assignee_id on public.tasks
  for each row execute function public.push_on_task_change();

drop trigger if exists task_logs_push on public.task_logs;
create trigger task_logs_push
  after insert or update of completed on public.task_logs
  for each row execute function public.push_on_task_done();

-- Trigger functions are not for clients to call.
revoke execute on function public.push_member_name(uuid)
  from public, anon, authenticated;
revoke execute on function public.push_on_task_change()
  from public, anon, authenticated;
revoke execute on function public.push_on_task_done()
  from public, anon, authenticated;

-- To try it, with two accounts in one group: close or minimise the app on the
-- second one, make a task "for everyone" on the first, then tick it. Each should
-- arrive as a notification. The queue empties as they are sent:
--   select * from public.push_outbox;
