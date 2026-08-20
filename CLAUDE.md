# todo_app — project reference

Flutter app: recurring-task / habit tracker with a day timeline. UI strings are
Russian (`ru_RU` only), code and comments are English. Not a git repo.

The app is called **Nook**. The name lives in `appName`
([lib/settings/app_version.dart](lib/settings/app_version.dart)) and is repeated
in every platform manifest (Android label, iOS `CFBundleDisplayName` /
`CFBundleName`, `web/index.html` + `web/manifest.json`, macOS `PRODUCT_NAME`,
the Linux and Windows window titles); `test/app_name_test.dart` reads them back
and fails on drift. The Dart package, the application id `com.yourname.todo_app`
and the desktop binary names are still `todo_app` — they are identifiers, not
the name, and renaming them is a separate move.

Keep this file current when structure, schema or invariants change.

## Toolchain & commands

| | |
|---|---|
| Flutter | 3.44.2 stable · Dart 3.12.2 (`sdk: ^3.12.2`) |
| Run | `flutter run` |
| Tests | `flutter test` (`flutter test test/<file>.dart -n '<name>'`) |
| Lints | `flutter analyze` (`package:flutter_lints/flutter.yaml`, no custom rules) |
| Codegen | `dart run build_runner build --delete-conflicting-outputs` |
| Android APK | `flutter build apk --debug` (verified building) |
| Release APK | `flutter build apk --release --no-tree-shake-icons [--split-per-abi]` |

**Test status (last checked 2026-08-20): 258 pass, 2 fail.**
- `test/widget_test.dart` — stale Flutter counter template; asserts a counter
  that never existed and pumps `MyApp` without the required
  `sharedPreferencesProvider` override. Delete or rewrite.
- `test/repro_test.dart` — real layout bug: `RenderFlex` overflows 4px in the
  timeline row `Column` at [task_timeline.dart:569](lib/widgets/home/task_timeline.dart#L569),
  only at 720x1280. Other sizes pass.

**`--no-tree-shake-icons` is not optional.** Task icons are stored as a code
point in `tasks.iconCodePoint` and rebuilt at runtime as
`IconData(codePoint, fontFamily: 'MaterialIcons')`, which the icon tree-shaker
cannot follow — a release build without the flag fails outright with "Avoid
non-constant invocations of IconData". The whole Material icon font ships as a
result (~1.6 MB). The release build signs with the **debug** keystore (the
template TODO in [android/app/build.gradle.kts](android/app/build.gradle.kts)
is still open), which is fine for sideloading and not for the Play Store. With
`--split-per-abi` each ABI gets its own versionCode (arm64 = 2001), so a
universal APK (versionCode 1) cannot be installed over a split one.

## Stack

- **State**: Riverpod (`flutter_riverpod` 2.x, `Notifier`/`StreamProvider`), no codegen.
- **DB**: Drift + `drift_flutter` (SQLite, reactive streams).
- **Prefs**: `shared_preferences` (theme mode, accent colour).
- **Notifications**: `flutter_local_notifications` + `timezone` /
  `flutter_timezone`. Needs `isCoreLibraryDesugaringEnabled` and the
  `desugar_jdk_libs` dependency in [android/app/build.gradle.kts](android/app/build.gradle.kts)
  — the build fails without them.
- **Calendar**: `table_calendar`. **Dates**: `intl` (`ru_RU`).
- **Declared but unused**: `go_router`, `fl_chart`, `uuid`, `path`. Navigation is
  plain `Navigator.push` + `IndexedStack`; there are no charts yet.

## Layout

```
lib/
  main.dart                      entry, ProviderScope, MainScreen, _buildTheme
  database/
    enums.dart                   TaskStatus, RepeatType, TrackingMode, EventType
    tables.dart                  Tasks, TaskLogs, TaskSessions, Events
    app_database.dart            AppDatabase, schemaVersion 7, migrations
    app_database.g.dart          generated — never edit
    providers.dart               db/dao providers + task & log StreamProviders
    daos/tasks_dao.dart          tasks, logs, sessions: CRUD + watch* + toggling
    daos/events_dao.dart         events CRUD (unused by the UI so far)
  pages/
    home_page.dart               calendar + day schedule (nav index 1)
    habits_page.dart             tabs "Привычки" / "Задачи" (nav index 0)
    diary_page.dart              stub, title only (nav index 2)
    settings_page.dart           appearance, reminders, version (nav index 3)
    appearance_page.dart         theme mode + accent colour
    create_task_page.dart        the task form, 2200 lines — see below
    timeline.dart                fully commented-out dead file
  notifications/
    timer_notification.dart      TimerNotification + timerNotificationsFor — pure
    task_reminder.dart           TaskReminder + taskRemindersFor — pure
    app_notifications.dart       AppNotifications — the whole plugin side
    providers.dart               appNotificationsProvider, runningTimer…,
                                 taskRemindersProvider
  settings/
    theme_provider.dart          sharedPreferencesProvider, themeMode, appColor
    notification_settings.dart   taskRemindersEnabledProvider (default on)
    app_version.dart             appName + appVersion — held in step by tests
  utils/recurrence.dart          the scheduling rules — single source of truth
  utils/task_colors.dart         foregrounds for content on a task colour
  utils/task_palette.dart        the seven colour families, accent + light tone
  utils/tracking.dart            counterTarget — a counter's effective target
  utils/surfaces.dart            page / card / row / inset / chip tones, both themes
  widgets/
    app_bottom_nav_bar.dart      AppNavItem, AppBottomNavBar (+ centre button)
    color_picker_row.dart        ColorPickerRow.colors — task colour palette
    icon_picker_sheet.dart       IconPickerSheet
    subtask_progress.dart        SubtaskProgress — the "done/total" read-out
    home/task_calendar.dart      TableCalendar wrapper, ≤4 task dots per day
    home/day_schedule_section.dart  swipe-between-days wrapper of the timeline
    home/task_timeline.dart      TaskTimeline, 1000 lines — see below
    home/schedule_drag_handle.dart
    habits/habits_grid.dart      HabitsGrid + HabitCard (+ mark/counter/timer)
    habits/tasks_list.dart       TasksList — non-repeating tasks, grouped
    habits/habit_day_state.dart  HabitDayState, habitDayState, isHabitDayMarkable
    habits/habit_actions_sheet.dart  showHabitActionsSheet
    habits/habit_history_sheet.dart  showHabitHistorySheet
    habits/task_actions_sheet.dart   showTaskActionsSheet
```

`lib/models/` mentioned in `.cursor/rules/architecture.mdc` does not exist; that
file also predates several columns. **This file is the current one.**

## Data model

One table (`tasks`) holds everything: habits, one-off tasks and subtasks.

- **Habit** = `repeatType != null` → "Привычки" tab + habit grid.
- **Task** = `repeatType == null` → "Задачи" tab, grouped overdue/today/upcoming/undated.
- **Subtask** = `parentId != null`. Root queries filter `parentId IS NULL`.

### tasks
| Column | Type | Notes |
|---|---|---|
| id | int PK | |
| parentId | int? | self-ref → tasks.id; non-null ⇒ subtask |
| title / description | text / text? | |
| status | TaskStatus | `active` \| `paused` \| `archived`; UI filters to active |
| repeatType | RepeatType? | `daily` \| `weekly` \| `monthly` \| `custom`; null ⇒ one-off |
| repeatInterval | int? | "every N"; null/`<1` ⇒ 1. `daily` ignores it |
| repeatDaysMask | int? | bitmask, day `d` → bit `d-1`. weekly: `DateTime.weekday` 1–7; monthly: 1–31. null ⇒ fall back to anchor's weekday/day |
| trackingMode | TrackingMode | `checkbox` \| `counter` \| `timer` \| `value` — **`value` is parked**, see below |
| targetDurationMinutes | int? | timer target; 0 in the form ⇒ null |
| targetValue | double? | counter *and* value target. `value`: 0 ⇒ null. `counter`: whole and ≥ 1 — read it through `counterTarget(task)`, never raw |
| iconCodePoint / colorValue | int? / int? | `IconData(..., fontFamily: 'MaterialIcons')` / `Color(v)` |
| scheduledTimeMinutes | int? | start, minutes from midnight; null ⇒ untimed strip |
| endTimeMinutes | int? | end; `> start` ⇒ ranged "pill" row on the timeline |
| startDate | DateTime? | first possible occurrence; null ⇒ backlog/undated |
| createdAt / updatedAt | DateTime | |

`task_logs`: `id, taskId → tasks.id, date, completed bool, value double?` — one
row per task per day. Subtasks log against **the parent's anchor date**, so
every screen reporting subtask progress must look logs up on that date. `task_sessions`: `id, taskId, startedAt, endedAt?,
durationSeconds?` — one row per timer run. **`endedAt == null` means the timer
is running now**; that start instant is the whole state of a live timer.
`events`: `id, title, description?, startDate, endDate?, type EventType` — table
+ DAO exist, no UI.

### Migrations
`schemaVersion` is **7**. `onUpgrade` in [app_database.dart:29](lib/database/app_database.dart#L29)
adds one column per version and is defensive: `addIfMissing` reads
`PRAGMA table_info(tasks)` first, because dev devices drifted. To change the
schema: edit `tables.dart` → bump `schemaVersion` → add an `if (from < N)` block
→ run build_runner.

## Scheduling — [lib/utils/recurrence.dart](lib/utils/recurrence.dart)

The only place that decides which days a task lands on. Everything (calendar
dots, timeline, habit squares) goes through it.

- `taskAnchorDate(task)` → `startDate ?? createdAt`, time stripped. First
  possible occurrence and the phase reference for intervals.
- `isTaskScheduledOn(task, day)` → false before the anchor, else the rule.
- `matchesRepeatRule(task, day)` → the rule alone, **ignoring the start date**.
  Used to tell "the habit did not exist yet" from "this day is not in the rule".
- `daysFromMask(mask, maxDay:)` / `daysToMask(days)` → bit `d-1`; empty ⇒ null,
  never 0. Max day 31, so a full mask stays inside 32 bits (web-safe).

Per type: `daily` = literally every day, stale intervals on old rows are ignored.
`custom` = every N days from the anchor. `weekly` = whole weeks counted between
Mondays, then the selected weekdays (or the anchor's). `monthly` = whole months,
then the selected days clamped to the month length — so "the 31st" reads as
"last day of the month" and never vanishes in February.

## Habit day states — [habit_day_state.dart](lib/widgets/habits/habit_day_state.dart)

`habitDayState(task, day, today:, completedDays:)` →
`done` (a mark always wins, even if the schedule later changed) > `off` (rule
does not cover the day) > `upcoming` > `beforeStart` (rule covers it, habit had
not started — drawn like `missed` but must not count as a failure) > `today` >
`missed`.

`isHabitDayMarkable(day, today:)` = `!day.isAfter(today)`. Every arrived day is
toggleable, including off-schedule ones — the schedule shows through the *look*
of a day, not by making it untouchable.

## Providers — [lib/database/providers.dart](lib/database/providers.dart)

`databaseProvider` → `tasksDaoProvider` / `eventsDaoProvider`;
`rootTasksProvider` (parentId null), `allTasksProvider` (incl. subtasks),
`subtasksProvider.family(parentId)`, `logsForTaskProvider.family(taskId)`,
`logsForDateProvider.family(date)`, `allLogsProvider`,
`logsBetweenProvider.family(DateRange)` (`DateRange` has value equality — the
family key depends on it), `openSessionsProvider` (timer runs in flight).

Theme: `sharedPreferencesProvider` (**must be overridden**, throws otherwise),
`themeModeProvider`, `appColorProvider` (palette in `appColorPalette`).

Who watches what: timeline → `allTasksProvider` + `logsForDateProvider`;
calendar & tasks list & habits grid → `rootTasksProvider`; habits grid & habit
sheet → `logsBetweenProvider`; task sheet → `subtasksProvider` +
`logsForDateProvider`.

## Screens

**MainScreen** ([main.dart:26](lib/main.dart#L26)) — `IndexedStack` over
`[HabitsPage, HomePage, DiaryPage, SettingsPage]`, starts at index 1;
`AppBottomNavBar`'s centre button pushes `CreateTaskPage`.

**Theme** (`buildAppTheme`, [main.dart:71](lib/main.dart#L71) — public so tests
can render a screen in the shipped theme) — seeded from the
accent colour but surfaces are pinned neutral, so picking a colour recolours
elements only. A near-black seed becomes white in dark mode. `onPrimary` is
whichever of black/white contrasts better with the accent (luminance > 0.179),
not `estimateBrightnessForColor`.

**Colour palettes** — one palette, seven families, two tones each
([utils/task_palette.dart](lib/utils/task_palette.dart)): `TaskSwatch.accent` is
what a task stores and what `appColorPalette` offers as the app accent;
`TaskSwatch.light` is the same family at ~78% white, for the large areas — the
timeline pill's body, the tinted box behind an icon. `taskLightTone(accent)`
resolves the pair, mixing one on the spot for a colour saved before this palette
existed. `taskBadgeSurface` picks the light tone on a light screen and a wash of
the accent on a dark one, where a near-white box would shout.

On the timeline the marker is the accent with a **white** glyph — 1.6:1 on the
yellow family, deliberate: it reads by its shape, and a white *label* on an
accent is never allowed. A pill that is less than a third elapsed draws its glyph
in `inkOn(light, accent, minContrast: 3)` instead, because white would vanish on
the light tone. `test/task_colors_test.dart` pins both rules.

Nothing drawn on a colour may hard-code black or white:

- on a **task colour** → [utils/task_colors.dart](lib/utils/task_colors.dart):
  `onTaskColor` (titles, primary icons) / `onTaskColorMuted` (labels) /
  `onTaskColorFaint` (decoration), plus `flattenOn(surface, overlay)` to resolve
  what shows through a translucent layer (the habit card's white "glass"
  buttons) before asking for a foreground.
- on the **accent** → `colorScheme.onPrimary`.

Both flip at luminance 0.179, where black and white contrast equally (4.58:1),
so the worse of the two is never used. `test/task_colors_test.dart` asserts that
every swatch and every accent clears 4.5:1 — it fails if a colour is added that
cannot be written on.

**Dark theme** — surfaces come from [utils/surfaces.dart](lib/utils/surfaces.dart):
`pageSurface` / `raisedSurface` (card, sheet) / `rowSurface` (grouped list row) /
`insetSurface` (chip, field, unselected cell) / `disabledInsetSurface` /
`neutralChip` (selected tab, today's circle, a done habit card) /
`surfaceShadow`. Light values are
exactly the old hard-coded ones; dark ones climb the neutral ladder pinned in
`buildAppTheme`, lightest = most raised (a shadow on near-black shows nothing, so
things lift by tone). Text is `onSurface` / `onSurfaceVariant` (+ alpha for
dimmer roles), hairlines `outlineVariant`.

A colour used as **ink** on a surface goes through `inkOn(surface, colour)`
([utils/task_colors.dart](lib/utils/task_colors.dart)): it walks the colour's
lightness until it clears 4.5:1 and leaves it alone when it already does. That is
what keeps the sheets' semantic colours (indigo "изменить" at 2.6:1 on a dark
sheet, amber "архив") readable in both themes.

Every screen is theme-driven now: the day-schedule block, `create_task_page`,
the icon picker, all three bottom sheets, the habits screen (date heading, tab
bar, task rows, empty states) and the calendar. `test/timeline_dark_theme_test.dart`
and `test/dark_theme_surfaces_test.dart` render them in the real dark theme and
fail on a white slab or a label under 3:1.

Two traps worth knowing:
- `table_calendar` ships hard-coded greys for a white calendar (#4F4F4F day-of-week
  headers, #5A5A5A weekends, #AEAEAE outside days). They are invisible on a dark
  page, so `daysOfWeekStyle` and every `CalendarStyle` text style are spelled out
  explicitly — in `task_calendar` **and** in `habit_history_sheet`.
- The task colour used as ink (tasks-list icon and checkbox, calendar dots) goes
  through `inkOn(..., minContrast: 3)`, so a pale swatch is darkened until it is
  visible. It is no longer literally the stored colour — `task_calendar_test`
  reads the expected dot colour through `inkOn` rather than comparing to the
  swatch.

**TaskTimeline** ([task_timeline.dart](lib/widgets/home/task_timeline.dart)) —
vertical, time-proportional (`pxPerMin = 1.4`). Timed tasks are rows (point or
duration "pill"); untimed ones go to the horizontal `_UntimedStrip` above.
`TaskTimeline.rowHeightFor(task, hasSubtasks:)` is shared with the gap rows.
A ticker drives `_NowMarker` — cancel it on dispose (there is a test for it).

**Timer habits** (`_TimerButton`, [habits_grid.dart](lib/widgets/habits/habits_grid.dart))
— a run is `TasksDao.startTimer` / `stopTimer`: start opens a `task_sessions`
row, stop closes it and folds its seconds into that day's `task_logs.value`,
capping at the target and ticking `completed` once reached. Pausing never
*clears* a tick. A run is banked against **the day it began on**, so a session
across midnight does not land on the wrong day, and a run left open by a crash is
banked by the next `startTimer` rather than lost. The widget holds no elapsed
count: it derives everything from `loggedSeconds` + `runningSince` and only
repaints once a second.

**Timer notifications** ([lib/notifications/](lib/notifications/)) — a running
timer posts an ongoing shade entry whose countdown **Android renders itself**
from `when` + `chronometerCountDown`, plus a `zonedSchedule`d "time is up" alert,
so both stay right while the app is dead. Split on purpose: `timerNotificationsFor`
decides *what* should be shown and is plain testable logic; `TimerNotifications`
only posts it, wrapping every platform call so a refused permission never breaks
a timer. `_MyAppState.initState` subscribes with `listenManual(fireImmediately:
true)` — `ref.listen` cannot fire for a run left over from the last launch.
Permissions are asked for on the first run that needs them, not at startup —
see **The notification permission** below. Android only for the live countdown;
iOS gets the completion alert, and a live lock-screen timer there would need an
ActivityKit Widget Extension in Swift.

Verified on an Android 16 emulator: the ongoing entry posts with a live
countdown, the completion alarm registers, and both clear when the run stops.
`SCHEDULE_EXACT_ALARM` is declared but **never requested from code** — the
request drops the user into a system settings screen mid-task — so the
completion alert normally lands on the inexact fallback (a few minutes' window).
Offering exact alarms as a deliberate opt-in is still open.

**Task reminders** — every task or habit with `scheduledTimeMinutes` is
`zonedSchedule`d for each occurrence in the next
`defaultReminderHorizonDays` (7), capped at `maxScheduledReminders` (64,
nearest first). Skipped when the occurrence has passed, the day is ticked, the
task is archived, or it is a subtask. Reminder ids start at
`AppNotifications.reminderIdBase` (1_000_000) so they can never collide with a
timer id, and are a pure function of (taskId, day) so a reschedule replaces
rather than duplicates. What is already scheduled is read back with
`pendingNotificationRequests()` — never remembered in memory — and the
`TaskReminder.fingerprint` rides along as the **payload**, which is the only
field that comes back, so a renamed or re-timed task is detected and replaced.
The user's switch is `taskRemindersEnabledProvider`; `syncReminders` takes it as
`enabled` rather than reading an empty list, because "off" and "no tasks" have
to cancel differently.

**The notification permission** — nothing is asked for at startup. The lazy ask
lives inside the syncs: `sync` returns before waking the plugin when nothing is
running and nothing is posted, and `syncReminders` passes
`requestPermission: target.isNotEmpty`, so an install that never runs a timer
and owns no timed task is never prompted. `_requestPermission` is spent once per
launch; the platform call itself is `_askPlatform`.

That alone left a fresh install with no way to grant anything — the switch is on
by default, and until a task carries a time there is nothing to schedule and
nothing to ask about — so there is a second, explicit path:
`AppNotifications.requestPermission()` asks whether or not there is something to
show, and is called when the user turns the reminders switch **on**.
`notificationsEnabled()` reads the system's answer back (`areNotificationsEnabled`
on Android, `checkPermissions().isAlertEnabled` on iOS, `null` where there is
nothing to ask) and `openSystemSettings()` opens the app's page there — the only
way out of a refusal, because Android answers a second request with a silent
`false` once the user has said no.

`notificationPermissionProvider` (`AsyncNotifier<bool?>`) holds that answer:
never cached across a resume, re-read by `SettingsPage`'s
`didChangeAppLifecycleState`, since granting happens outside the app and nothing
reports it back. Flipping to granted **re-runs `syncReminders`** — reminders that
failed while the permission was missing are not retried by anything else, no task
having changed. The settings screen warns only on a definite `false` *and*
reminders on: `null` is "nothing to ask", not a refusal.

**The parked `value` mode** — `_ModeSelector._blocked` in
[create_task_page.dart](lib/pages/create_task_page.dart) holds the tracking
modes the form refuses to hand out. `TrackingMode.value` sits there because
nothing reads a free-form value yet, so a task saved with it behaves like a
checkbox that quietly remembers a number. The enum, the column and every value
task already stored are untouched: the tile is greyed out and inert, but a task
that *already* uses the mode still shows it selected and keeps it on save, so
editing one cannot silently rewrite what it tracks. Switching such a task away
is therefore one-way. Emptying `_blocked` brings the mode back; the value
stepper and its decimal sheet are still there and still tested, reached through
edit mode.

**CreateTaskPage** ([create_task_page.dart](lib/pages/create_task_page.dart)) —
`TaskFormMode.create | edit | clone`; edit/clone assert a source task. Save
logic at [:258](lib/pages/create_task_page.dart#L258). Form-to-DB conversions
worth remembering: repetition off ⇒ `repeatType` null; `daily` or interval ≤ 1 ⇒
`repeatInterval` null; a target of 0 ⇒ null; mask null unless weekly/monthly.
Edit uses `updateTaskById` (partial write, explicit `Value(null)` clears);
create uses `insertTask` with `Value.absent()` for untouched columns. Subtasks
are editable drafts (`_SubtaskDraft`): rows added → insert, renamed → update,
removed → `deleteTaskCascade`; a tick writes a log via `setLog`. Cloning copies
through those drafts, **not** `dao.copySubtasks` (which stays as a DAO-level
helper).

## Branding — the launcher icon

The logo is a 3D calendar-with-clock badge. `assets/branding/` holds the
sources; they are **not** listed under `flutter: assets:` because nothing draws
them at runtime — they exist only to generate the platform icons:

| File | What it is | Used for |
|---|---|---|
| `app_icon_source.png` | the untouched render, badge floating in a soft drop shadow | the master; everything below is derived from it |
| `app_icon.png` | badge cropped square, shadow removed, transparent rounded corners | Android legacy mipmaps |
| `app_icon_full_bleed.png` | the badge over a blurred, enlarged copy of itself, opaque | iOS / macOS / Windows / web, where corners are rounded by the platform and alpha is unwelcome |
| `app_icon_foreground.png` | badge at 82% on transparent | Android adaptive foreground |
| `app_icon_background.png` | only the blurred backdrop | Android adaptive background |
| `notification_icon.png` | flat white calendar-with-check silhouette, drawn from scratch | master for `res/drawable-*/ic_notification.png` |

Regenerate every platform with `dart run flutter_launcher_icons` after touching
any of them; the config is the `flutter_launcher_icons:` block in
[pubspec.yaml](pubspec.yaml). Two settings there are deliberate:
`adaptive_icon_foreground_inset: 0`, because the badge is already inset to 82%
inside the foreground image and the plugin's default 16% would shrink it twice;
and `remove_alpha_ios: true`, because iOS rejects an icon with an alpha channel.
The 82% is what keeps the calendar clear of the mask — Android only guarantees
the middle 66% of an adaptive icon survives a round or squircle cutout.

The **notification small icon** is a separate drawing and not generated by the
plugin: Android renders a small icon from its alpha channel alone, so the
full-colour launcher icon would come out as a white blob. `ic_notification.png`
in `res/drawable-{m,h,xh,xxh,xxx}dpi` is the logo reduced to one silhouette — a
solid calendar page with the checkmark knocked out of it — and
[app_notifications.dart:294](lib/notifications/app_notifications.dart#L294)
points `AndroidInitializationSettings` at it. It is sized 24/36/48/72/96 px,
i.e. 24dp, with the artwork inset ~8% so nothing touches the edge.

Verified on the Android 16 emulator: the launcher shows the adaptive icon under
a circular mask with the calendar fully inside it and the label "Nook", and a
running timer's shade entry resolves its small icon to `drawable/ic_notification`
(`dumpsys notification`). Android 16 itself draws the app's launcher icon as the
notification avatar, so the silhouette only surfaces on the lock screen, in the
status bar and on older releases.

## Conventions

- Widgets and providers never touch the database directly — always a DAO.
- `watch*` (streams) for UI, `get*` (futures) only for form seeding.
- `.g.dart` is generated; edit the source and re-run build_runner.
- Dates are compared date-only; strip the time before use.
- New scheduling logic belongs in `recurrence.dart`, not in a widget.
- Anything measuring elapsed time reads the wall clock against a stored instant.
  Never accumulate seconds in a widget: a `Ticker`/`AnimationController` freezes
  the moment the app leaves the foreground, so it under-counts and loses the run
  on restart. A ticker may ask for a repaint, never carry the time itself.
- Screens that show subtask progress watch `allTasksProvider` and group by
  `parentId`, then filter roots — subtasks are never rows of their own.
- Tests: DAO-level use `AppDatabase.forExecutor(NativeDatabase.memory())`;
  widget tests override the providers with `Stream.value(...)` and wrap in a
  `MaterialApp` with the `ru_RU` locale + `initializeDateFormatting('ru_RU')`.

## Other working directory

`/home/user/Desktop/work/workaxle/feature-flags/rollouts/features.yaml` — a
separate work repo (feature-flag rollouts), unrelated to this app.
