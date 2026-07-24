# Cross-Platform Scheduler Options

## Question

For PostgreSQL / pgBackRest backup jobs, what are the viable cross-platform scheduling approaches?

## Sources

- systemd timers: https://www.freedesktop.org/software/systemd/man/systemd.timer.html
- Windows scheduled tasks: https://learn.microsoft.com/en-us/powershell/module/scheduledtasks/register-scheduledtask
- macOS launchd timed jobs: https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/ScheduledJobs.html
- PM2 restart strategies: https://pm2.keymetrics.io/docs/usage/restart-strategies/
- PM2 startup persistence: https://pm2.keymetrics.io/docs/usage/startup/
- Windows app notifications: https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/app-notifications-quickstart
- Go scheduler library: https://pkg.go.dev/github.com/go-co-op/gocron/v2
- Go Windows toast library: https://pkg.go.dev/github.com/go-toast/go-toast
- Go cross-platform notification library: https://github.com/gen2brain/beeep
- Local systemd-service-manager docs: `scripts/bash/systemd-service-manager/README.md`
- Local PM2 pattern: `config/network/rathole/start.ps1`

## Options

### Option A: Native OS Scheduler Adapters

Generate or document scheduler targets per OS:

- Linux: systemd timer, preferably through this repo's `systemd-service-manager` when available.
- Windows: Task Scheduler via `Register-ScheduledTask`.
- macOS: launchd plist with `StartCalendarInterval`.

Pros: Best reliability, native logs/lifecycle, reboot behavior, permissions, and service account support.
Cons: More templates and validation paths; no single file works unchanged on all OSes.

### Option B: PM2 as a Cross-Platform Scheduler Layer

Use PM2 ecosystem files with `cron_restart` to trigger the backup app at scheduled times.

Pros: Similar commands across Windows/macOS/Linux when Node + PM2 are installed; repo already has PM2 patterns.
Cons: PM2's cron model is restart-oriented, so one-shot backups need careful `autorestart` / exit-code settings.

### Option C: Plain cron

Use crontab on Unix-like systems.

Pros: Simple, common, very low ceremony.
Cons: Not Windows-native; weaker logs/status; less explicit environment and missed-run behavior than systemd timers.

### Option D: Container / Platform Scheduler

Use Kubernetes CronJob, CI schedule with self-hosted runner, NAS scheduler, or another orchestration platform.

Pros: Good when the deployment platform already exists.
Cons: Overkill for a local macmini/Tailscale backup setup; ties backups to a specific platform.

### Option E: Long-Running PowerShell Scheduler Loop

Run a persistent `pwsh` process that sleeps and invokes the toolkit on schedule.

Pros: The script itself can be cross-platform.
Cons: Recreates a supervisor poorly; still needs PM2/systemd/Task Scheduler/launchd to keep it alive. Not recommended for backup reliability.

### Option F: Node Scheduler Service Managed by PM2

Run a small long-lived Node service under PM2. The Node service owns schedule parsing, non-overlap, logging, and child-process execution of `Postgres-Toolkit.ps1 pgbackrest ...`; PM2 owns process supervision and reboot persistence.

Potential implementation shape:

- Source: `scripts/node/src/postgres-scheduler/**` or a dedicated `scripts/node/src/pgbackrest-scheduler/**`.
- Config: committed example under `config/database/backup/pgBackRest/`, real `.local` ignored.
- PM2 app: one fork-mode instance, no cluster mode.
- Scheduler library: `node-cron` is enough for MVP because it supports timezone and no-overlap scheduling options.
- Execution: use `node:child_process` to spawn `pwsh -NoProfile -File <Postgres-Toolkit.ps1> pgbackrest ...`.

Pros: One operational model across Windows/macOS/Linux when Node + PM2 are available; better logs and retry behavior than PM2 `cron_restart` alone; avoids OS-specific unit/plist/task templates for the MVP.

Cons: It is a real service that must be tested and maintained; missed-run semantics after downtime must be defined; single-instance enforcement matters if PM2 cluster mode or multiple machines run the same schedule.

Windows notification note: Node can use a notification library or call a PowerShell notification helper after each backup, but Windows toast reliability still depends on running in the interactive user's session with a stable app identity. If PM2 is installed as a background service under `SYSTEM`, desktop notifications may not appear for the logged-in user.

### Option G: Go Scheduler Service Managed by PM2

Build a small Go service binary and let PM2 manage it with `interpreter: none`. The Go service owns schedule parsing, non-overlap, command execution, and notification dispatch; PM2 still owns process supervision and restart.

Potential implementation shape:

- Source: a new Go module under `projects/clis/pgbackrest-scheduler` or a similar project path.
- Scheduler library: `github.com/go-co-op/gocron/v2`, which supports scheduler location/timezone, concurrency limiting, monitors, and locking-related extension points.
- Windows notifications:
  - `github.com/go-toast/go-toast` for Windows-specific toast notifications. It exposes `AppID`, `Title`, `Message`, icon/audio/action fields, then invokes PowerShell to display the toast.
  - `github.com/gen2brain/beeep` for a simpler cross-platform notification abstraction.
- Execution: use `os/exec` to run `pwsh -NoProfile -File <Postgres-Toolkit.ps1> pgbackrest ...`.

Pros: Best runtime distribution story; one compiled binary, low memory, no Node runtime for the service itself; Go scheduling and process execution are a natural fit.

Cons: This repo currently has no Go module/service precedent, so it introduces a new build/test/release lane. Windows toast constraints remain the same as Node: the process must run where the logged-in user can receive desktop notifications.

## Windows Notification Design Notes

Windows desktop toast is not just a language choice. Key constraints:

- The scheduler must run in the interactive user's context if the goal is a local desktop toast.
- A stable app identity/AppID is important for notification grouping and reliability.
- Running as a Windows service or under `SYSTEM` is good for unattended operation but bad for per-user desktop notifications.
- If the backup actually runs on macmini/Linux and the user wants a Windows desktop toast, the scheduler/notification bridge needs to run on the Windows machine or send a remote notification through another channel such as ntfy, email, webhook, Telegram, or Teams.

This means the project should separate notification delivery from backup execution. A scheduler can emit:

- local desktop notification,
- log-only notification,
- webhook notification,
- email or ntfy notification,
- disabled notification.

## Recommendation

Use a cross-platform backup CLI plus scheduler adapters:

1. Keep `Postgres-Toolkit.ps1 pgbackrest ...` as the only backup execution path.
2. Expose the toolkit through `tool.psd1` and `Manage-BinScripts.ps1`.
3. For MVP, either support PM2 ecosystem templates directly, or build a Node/Go scheduler service managed by PM2 if richer logs/retry/non-overlap/notification behavior is required.
4. Document native alternatives for Linux, Windows, and macOS; avoid pretending that one scheduler is equally native everywhere.

Future toolkit command shape could be:

```powershell
Postgres-Toolkit.ps1 schedule render --target pm2 --type incr --schedule '0 3 * * *'
Postgres-Toolkit.ps1 schedule render --target systemd --type incr --schedule '0 3 * * *'
Postgres-Toolkit.ps1 schedule render --target windows-task --type incr --schedule daily
Postgres-Toolkit.ps1 schedule render --target launchd --type incr --schedule daily
```

If choosing the Node service route, the MVP command shape can stay simpler:

```bash
pm2 start config/database/backup/pgBackRest/pgbackrest-scheduler.pm2.config.cjs
pm2 logs pgbackrest-scheduler
pm2 save
```
