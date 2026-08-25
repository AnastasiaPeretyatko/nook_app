enum TaskStatus { active, paused, archived }

enum RepeatType { daily, weekly, monthly, custom }

enum TrackingMode { checkbox, counter, timer, value }

enum EventType { personal, work, reminder, holiday }

/// Where a diary entry sits. Mutually exclusive, which is what makes the diary's
/// tabs a filter on one column: "Черновики", "Архив" and — for
/// [DiaryEntryStatus.normal] — "Все". Being a favourite is orthogonal to all
/// three and lives in its own flag.
enum DiaryEntryStatus { draft, normal, archived }
