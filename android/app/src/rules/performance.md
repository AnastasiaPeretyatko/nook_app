# Performance and Updates

- Prefer event-driven refreshes after relevant task, project, or widget-configuration changes over frequent polling.
- Avoid refresh storms: coalesce duplicated update requests while preserving correctness.
- Update affected instances only where supported and practical. Multiple widgets showing the same project must stay consistent.
- Keep rendering work lightweight; prepare, filter, sort, and serialize data before the UI layer.
- Avoid repeatedly parsing the same data per list row or reading the entire database for each checkbox tap.
- Do not introduce background loops, arbitrary timers, unnecessary network requests, or a Flutter engine startup just to render snapshots.
- Inspect actual refresh paths and logs before optimizing; do not rewrite the architecture speculatively.
- Respect Android background execution, battery, and launcher limitations.
- Use existing dependencies unless a measurable need justifies adding another.
