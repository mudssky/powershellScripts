# Systemd Service Manager

一个基于 Bash 的轻量 systemd `service` / `timer` 管理器。

## Build

```bash
bash scripts/bash/systemd-service-manager/build.sh
```

## Outputs

- `bin/systemd-service-manager`
- `scripts/bash/systemd-service-manager.sh`

## Test

```bash
pnpm run test:systemd-service-manager
```

## Quality Gate

```bash
pnpm run qa:systemd-service-manager
pnpm qa
```
