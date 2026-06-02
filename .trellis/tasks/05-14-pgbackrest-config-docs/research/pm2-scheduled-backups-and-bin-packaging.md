# PM2 Scheduled Backups and Bin Packaging

## Question

Can pgBackRest scheduled execution be managed with PM2, and how should that relate to this repo's PowerShell toolkit packaging and `bin/` shim generation?

## Sources

- PM2 Restart Strategies: https://pm2.keymetrics.io/docs/usage/restart-strategies/
- PM2 Ecosystem File: https://pm2.keymetrics.io/docs/usage/application-declaration/
- PM2 Startup Script: https://pm2.keymetrics.io/docs/usage/startup/
- Local pattern: `config/network/rathole/start.ps1`
- Local pattern: `config/network/rathole/rathole-*.pm2.config.cjs`
- Local packaging: `Manage-BinScripts.ps1`
- Local PostgreSQL bundle: `scripts/pwsh/devops/postgresql/build/Build-PostgresToolkit.ps1`

## Findings

PM2 can schedule work with `cron_restart`, but the official PM2 model is "restart an app at a cron time." For one-shot backup commands, this means the process must be registered with PM2 and configured carefully so a successful exit does not loop. The relevant PM2 controls are `cron_restart`, `autorestart: false`, and, when failure restarts are desired, `stop_exit_codes: [0]`.

PM2 can persist the configured process list across reboots with `pm2 startup` and `pm2 save`. That makes it attractive for machines that already use PM2 in this repo, such as the rathole template, but it is less native than systemd timers on Linux for pure scheduled jobs.

This repo already has a PM2 management style in `config/network/rathole/start.ps1`: a small wrapper validates files, builds PM2 invocation plans, supports `DryRun`, and keeps ecosystem config files next to local configuration. That pattern fits a pgBackRest scheduler wrapper if PM2 is selected.

`Manage-BinScripts.ps1` does not bundle source code. It generates `bin/*.ps1` shims that call source scripts by relative path. It also supports directory tools via `scripts/pwsh/**/tool.psd1`: the manifest exposes one entry script and hides internal `.ps1` files from `bin/`.

`Postgres-Toolkit.ps1` already has its own true bundle build step in `Build-PostgresToolkit.ps1`. The bundle concatenates the modular toolkit source into `scripts/pwsh/devops/Postgres-Toolkit.ps1` and copies Markdown help. That is the right distribution path for the toolkit itself.

## Repo Constraints

- `config/database/backup/pgBackRest/**` should contain templates and README, not a second maintenance script that duplicates toolkit behavior.
- `scripts/pwsh/devops/postgresql/**` is the modular source for the toolkit.
- `scripts/pwsh/devops/Postgres-Toolkit.ps1` is generated bundle output.
- `bin/` should be generated from `Manage-BinScripts.ps1`, not edited by hand.
- A directory tool manifest can expose `Postgres-Toolkit.ps1` under a stable `bin/` name while hiding internal implementation files.

## Feasible Approaches

### Approach A: PM2 Ecosystem Template Only

Add PM2 ecosystem config examples under `config/database/backup/pgBackRest/` that call the existing toolkit with `pgbackrest --action backup --type ...`. Users start them with raw PM2 commands.

Pros: Minimal code, aligned with "config directory only" constraint.
Cons: More manual PM2 operations; harder to test invocation planning.

### Approach B: PM2 Wrapper Plus Ecosystem Template

Add a small PM2 management wrapper, following `config/network/rathole/start.ps1`, plus ecosystem templates for full/diff/incr schedules. The wrapper would only manage PM2 start/stop/logs/status/save/config/dry-run and would not reimplement backup logic.

Pros: Nice operator UX, follows an existing local PM2 pattern, testable.
Cons: Adds another script in the config area, which slightly bends the current PostgreSQL spec unless the wrapper is treated as scheduling glue rather than backup logic.

### Approach C: Toolkit Scheduler Subcommand Plus Bin Manifest

Keep config templates in `config/database/backup/pgBackRest/`, add scheduler command generation/validation to `scripts/pwsh/devops/postgresql`, add `tool.psd1` so `Manage-BinScripts.ps1` exposes only the toolkit entry in `bin/`, and keep PM2 as one supported scheduler target.

Pros: Most consistent with the PostgreSQL toolkit spec and bundle pipeline; gives a clean `bin/Postgres-Toolkit.ps1` shim story; keeps scheduling command generation testable.
Cons: More implementation than a pure README/template change.

## Recommendation

Prefer Approach C if the goal is a durable project feature: keep pgBackRest execution inside the toolkit, expose it through the existing bundle and `Manage-BinScripts.ps1`, and treat PM2/systemd/cron as scheduler targets generated or documented by the toolkit.

If the immediate need is only "run this on my machine tonight," use Approach A first and document the exact PM2 ecosystem template.
