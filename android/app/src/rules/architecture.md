# Architecture

- These rules apply to Nook Android home-screen widgets implemented alongside Flutter. Inspect the existing implementation before editing.
- Keep UI, per-widget configuration, data access, action handlers, and synchronization as separate responsibilities; do not create extra layers just for their own sake.
- Prefer existing project patterns, shared models, services, and design conventions. Avoid duplicating business rules.
- UI rendering must not perform database access, network calls, or expensive data transformations.
- Keep widget snapshots small and self-contained. Treat the application's authoritative data store as the source of truth.
- Support multiple widget instances: persist settings by `appWidgetId`, including the selected project. Never use one global selected project.
- Update only instances affected by a change when feasible; clean up instance configuration when a widget is removed.
- Handle deleted projects, missing tasks, empty data, and process recreation.
- Do not launch a Flutter engine merely to redraw a widget if a reliable native data path already exists.
- Match the current technology: Glance-specific rules apply only to Glance; RemoteViews-specific rules apply only to RemoteViews.
