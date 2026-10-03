# Changelog

## 0.1.0 (2026-10-03)

First release.

- Bar widget: running timer as `H:MM · activity` (elided, `+N` for extra
  timers), dimmed when idle or offline, urgent colour when the token is
  rejected. Middle-click stops or restarts the last entry, right-click opens
  Kimai.
- Popup with Timer, Entries and Settings tabs: start (project, activity,
  description, tags, new tags), stop, restart from Recent, edit the running
  timer, browse days and edit finished entries, punch-mode aware.
- Settings: server URL + API token (stored in the keyring, passed to curl on
  stdin), refresh interval, label width, timezone warning.
- IPC: `omarchy-shell kimai toggle|stop|restartLast|refresh|status`.
- Works offline (stale state with automatic recovery and back-off).
