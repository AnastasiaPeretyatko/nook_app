# Verification and Delivery

- Before editing: inspect existing widget providers, Glance/RemoteViews code, configuration, data flow, callbacks, and refresh triggers. Identify the smallest safe change.
- After editing: run relevant tests and Android compilation/build checks if the environment permits. Report exact commands and outcomes; never claim a check ran when it did not.
- Test task completion, reopening, rapid repeated taps, offline/error handling, app restarts, and widget process recreation.
- Test multiple instances configured to the same and different projects, project deletion, and widget removal/cleanup.
- With a long task list, scroll to the middle, toggle several tasks, and verify: no avoidable blink, no unexpected scroll reset, no item shuffle, no blank content, and no duplicate action.
- Cover compact and expanded widget sizes, long labels, and representative Android versions/launchers during the user's manual validation.
- Automated unit tests cannot prove visual stability: explicitly state what remains for manual validation.
- Do not launch an emulator, a device, or on-device widget tests. The user performs manual visual validation.
- Keep changes focused. In the completion report list modified files, behavior changes, checks performed, outstanding risks, and platform limitations.
