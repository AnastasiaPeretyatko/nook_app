# Rendering and UX

- The primary UX target is a stable, responsive widget: no avoidable flashes, blank intermediate states, or jump to the top of a scrollable task list.
- Before changing rendering, identify whether the issue comes from widget-wide updates, collection replacement, unstable item identity, sorting/filtering, or duplicate refreshes.
- For Glance collections, use stable persistent item IDs where the API supports them (e.g., `LazyColumn` `itemId`). Never use array indexes, random IDs, or IDs regenerated on refresh.
- For RemoteViews collections, use supported stable-ID and data-change mechanisms where applicable. Do not assume Glance APIs and direct RemoteViews update methods are interchangeable.
- Preserve ordering and the position of unchanged items across checkbox toggles. Do not automatically hide or move completed tasks unless the feature explicitly requires this.
- Prefer updating only what changed when the chosen API permits it. Avoid rebuilding or clearing the entire collection to show a local status change.
- Preserve scrolling during updates where supported by Android version and launcher. Do not claim scroll preservation is guaranteed on all devices.
- Do not use arbitrary delays or forced scroll-to-position hacks to conceal rendering problems.
- Ensure long titles, different font scales, compact widget sizes, resize behavior, contrast, and touch targets remain usable.
- Do not change Nook's existing visual language without a design requirement.
