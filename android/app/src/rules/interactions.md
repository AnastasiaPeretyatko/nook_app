# Interactions and Sync

- Every action must target the correct widget instance and task using persistent IDs.
- Marking a task complete/incomplete must update authoritative state, reflect the new status in affected widgets, and synchronize with the Flutter UI as needed.
- Prevent duplicate processing from rapid taps or repeated delivery. Define explicit behavior for concurrent and out-of-order changes; do not rely on an unguarded toggle operation.
- Keep expensive work off the main thread. Use appropriate Android asynchronous/background mechanisms and respect their execution limits.
- Prefer a single coherent refresh after a successful state change; avoid both a local refresh and a redundant synchronization-triggered refresh.
- For optimistic UI, provide rollback or reconciliation if persistence fails. Never leave a checkbox permanently inconsistent with stored data.
- Do not launch the app for an interaction the widget can handle safely; use explicit deep links when navigation is intended.
- Do not clear otherwise valid widget content during loading, offline conditions, or recoverable failures.
- Do not log private task titles or sensitive content unnecessarily.
