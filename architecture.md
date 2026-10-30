# Архитектура

Nook — Flutter-приложение: трекер привычек и задач с таймлайном дня, дневником и
(по желанию) трекером цикла. Все данные живут на телефоне; аккаунт и синхронизация
с сервером — необязательное дополнение.

## 1. Общая схема (флоу)

### Главная идея

Приложение **работает без интернета и без аккаунта**. Локальная база на телефоне —
главная копия данных. Сервер (наш собственный, NestJS на Render + Neon) — только «зеркало» для переноса данных
между устройствами.

### Как данные доходят до экрана

```
 Экран (pages/ + widgets/)
   │  смотрит (ref.watch)           ▲ перерисовка при любом изменении
   ▼                                │
 Провайдеры Riverpod (database/providers.dart)
   │  берут данные у                │ стримы (Stream) от базы
   ▼                                │
 DAO (database/daos/) ──────────► SQLite через Drift (app_database.dart)
```

- **Экран никогда не лезет в базу сам** — только через DAO (класс с запросами к
  одной группе таблиц: `TasksDao`, `DiaryDao`, `CycleDao`, `EventsDao`).
- Для экрана данные приходят **стримами**: что-то записали в базу — экран
  перерисовался сам, ничего вручную обновлять не нужно.
- **Правила расписания** (в какие дни привычка «выпадает») лежат в одном месте —
  [lib/utils/recurrence.dart](lib/utils/recurrence.dart). Календарь, таймлайн и
  квадратики привычек спрашивают у него, сами не считают.
- Остальная логика (статистика, серии, цикл, пересечения задач) — «чистые»
  функции в `lib/utils/` и `lib/widgets/habits/*_stats.dart`: берут данные,
  возвращают результат, ничего не трогают снаружи. Поэтому их легко тестировать.

### Запуск приложения

1. [lib/main.dart](lib/main.dart): `main()` поднимает даты (`ru_RU`),
   `SharedPreferences`, будит сервер (`warmUpServer` — запрос `/health` без ожидания:
   нет сети — приложение всё равно откроется).
2. `ProviderScope` с этими значениями → `MyApp` → тема (`buildAppTheme`).
3. `home:` = `SyncScope(HomeWidgetScope(MainScreen()))` — две «обёртки без
   внешнего вида»:
   - `SyncScope` решает, **когда** синхронизировать (при изменениях, при
     открытии и возврате в приложение; сворачивание отправляет накопленное;
     таймера нет);
   - `HomeWidgetScope` держит в актуальном состоянии виджет на рабочем столе.
4. `MainScreen` — 4 вкладки (+ пятая «Цикл», если включена): **Привычки ·
   Задачи · Таймлайн · Дневник · (Цикл)**. Открывается на Таймлайне.
   Настройки — не вкладка, а экран из кнопки профиля.

### Синхронизация с сервером

```
Изменили запись → в базе ставится пометка «dirty» (ещё не отправлено)
        │
SyncController (КОГДА): через паузу после правки / после каждого подключения
        │               к сокету (запуск, возврат) / по звонку «changed» сервера /
        │               при сворачивании (отправить сразу)
        ▼
SyncService (КАК): 1) забирает чужое (`pull`; группы приходят в том же ответе)
        │            2) отправляет помеченное (`push`)
        │            правило конфликтов — merge.dart: «побеждает более поздняя правка»
        ▼
Сервер (REST + WebSocket «звонок»; каждый видит только свои строки)
```

- `payload.dart` переводит строку базы ↔ формат сервера.
- `first_sync.dart` — вопрос при первом входе: что делать с данными, которые уже
  лежат на телефоне (загрузить, оставить локально, присвоить новому аккаунту или
  стереть).
- Данные цикла уходят на сервер только по отдельному выключателю (это данные о
  здоровье).

### Уведомления

- `task_reminder.dart` и `timer_notification.dart` — «чистые»: решают, **что**
  показать.
- `app_notifications.dart` — единственное место, которое говорит с плагином
  Android/iOS: **показывает**. Сбой разрешения не ломает приложение.

### Виджет на рабочем столе (Android)

Dart считает, Kotlin рисует:

```
Dart (lib/home_widget/) → JSON-«payload» → HomeWidget (хранилище) → Kotlin
TodayWidgetProvider.kt рисует виджет
Нажатие на галочку → отдельный Dart-процесс → TasksDao.toggleCompletion
```

Подробности и ловушки — в навыке
[.claude/skills/home-screen-widget/](.claude/skills/home-screen-widget/SKILL.md).

## 2. Стек технологий

| Что | Чем |
|---|---|
| Фреймворк | Flutter 3.44 / Dart 3.12 |
| Состояние | `flutter_riverpod` 2.x (`Notifier`, `StreamProvider`, без кодогенерации) |
| Локальная БД | Drift + `drift_flutter` (SQLite, реактивные стримы), схема v19 |
| Настройки | `shared_preferences` (тема, акцент, переключатели, данные «О себе» и цикла) |
| Сервер и вход | свой сервер: `http` + `ApiClient`, `flutter_secure_storage`, `google_sign_in`; WebSocket на `dart:io`; контракт — `docs/own-backend/BACKEND_PLAN.md` |
| Push | `firebase_messaging` (токен уходит на наш сервер, он шлёт уведомления) |
| Уведомления | `flutter_local_notifications` + `timezone` + `flutter_timezone` |
| Виджет на рабочем столе | `home_widget` + Kotlin (`RemoteViews`) |
| Календарь / даты | `table_calendar`, `intl` (только `ru_RU`) |
| Дневник | `fleather` (редактор текста), `image_picker`, `path_provider` |
| Прочее | `connectivity_plus` (Wi-Fi), `flutter_lucide` (иконки), шрифт Onest |
| Тесты и инструменты | `flutter_test`, `flutter_lints`, `build_runner` + `drift_dev` (генерация кода БД), `flutter_launcher_icons` |
| Дизайн | система «Иней»: `AppPalette` ([lib/theme/app_palette.dart](lib/theme/app_palette.dart)), спецификация в `docs/design-handoff/` |

Подключены, но пока не используются: `go_router`, `fl_chart`, `uuid`, `path`.
Навигация — обычный `Navigator.push` и стопка вкладок.

Платформы: основная цель — Android (там же виджет); папки `ios/`, `macos/`,
`web/`, `linux/`, `windows/` есть, но проверялся в первую очередь Android.

## 3. Структура папок

```
todo.app/
├── lib/                  код приложения (разбор ниже)
├── test/                 ~70 тестов: DAO, чистая логика, экраны, синхронизация
├── supabase/             SQL прежнего сервера (Supabase) — только справочник, не используется
├── docs/                 own-backend/ (план переезда и контракт API), design-handoff/ (дизайн),
│                         supabase-setup.md (устарело)
├── assets/               шрифты Onest, assets/branding/ (исходники иконки)
├── android/              платформа; тут же Kotlin-код виджета
│   └── app/src/main/kotlin/…/  MainActivity.kt, TodayWidgetProvider.kt
├── ios/ macos/ web/ linux/ windows/   остальные платформы
├── CLAUDE.md             подробный справочник для работы с проектом
└── pubspec.yaml          зависимости и настройки сборки
```

### lib/

```
lib/
├── main.dart             точка входа, MainScreen (вкладки), тема
├── database/             всё про локальную базу
│   ├── tables.dart         таблицы (Tasks, TaskLogs, DiaryEntries, CycleDays …)
│   ├── enums.dart          TaskStatus, RepeatType, TrackingMode, EventType
│   ├── app_database.dart   сама база + миграции (.g.dart — генерируется, не править)
│   ├── providers.dart      провайдеры базы и потоки задач/отметок
│   └── daos/               tasks_dao, diary_dao, cycle_dao, events_dao
├── pages/                экраны целиком
│   ├── habits_page, tasks_page, home_page (таймлайн), diary_page, cycle_page
│   ├── create_task_page, create_note_page, note_view_page
│   ├── habit_detail_page, cycle_calendar_page, archive_page
│   └── settings_page, account_page, groups_page
├── widgets/              кусочки экранов
│   ├── habits/             привычки: сегодня, неделя, история, статистика
│   ├── home/               календарь и таймлайн дня
│   ├── diary/ cycle/       части дневника и цикла
│   ├── settings/           блоки настроек
│   └── …                   общие: нижняя панель, диалоги и шторки, карточки
├── utils/                «чистая» логика без экранов и базы
│   ├── recurrence.dart     правила расписания (единственный источник правды)
│   ├── overdue, day_plan, last_done, tracking, week   задачи и привычки
│   ├── cycle, cycle_stats, cycle_marks                цикл
│   ├── task_colors, task_palette, task_icons, surfaces   цвета и иконки
│   └── note_*, diary_groups                           дневник
├── settings/             настройки на SharedPreferences (тема, аналитика, синхр.…)
├── theme/                AppPalette — цвета дизайн-системы
├── sync/                 синхронизация: controller (когда), service (как),
│                         merge (кто победил), payload (формат), first_sync
├── api/                  ApiClient (токены, повторы), SyncApi, имя телефона
├── auth/                 вход на нашем сервере: репозиторий (почта, Google), ошибки
├── push/                 токен FCM → наш сервер, нажатие на уведомление
├── groups/               группы с общими задачами (запросы к серверу)
├── notifications/        напоминания и уведомления таймера
├── home_widget/          Dart-половина виджета на рабочем столе
├── data/  models/        пустые, остались от нереализованной раскладки
```

### Правила, которые держат структуру

- Виджеты и провайдеры не ходят в базу напрямую — только через DAO.
- Для экранов — `watch*` (стримы), `get*` (разовые запросы) — только чтобы
  заполнить форму.
- `*.g.dart` — генерируется: правим исходник и запускаем
  `dart run build_runner build --delete-conflicting-outputs`.
- Новая логика расписания — в `recurrence.dart`, а не в виджете.
- Изменили схему базы: правка `tables.dart` → поднять `schemaVersion` → блок
  `if (from < N)` в `onUpgrade` → build_runner.
