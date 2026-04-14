# Systemd Service Manager

一个基于 Bash 的轻量 systemd `service` / `timer` 管理器。

## Build

```bash
bash scripts/bash/systemd-service-manager/build.sh
```

## Outputs

- `bin/systemd-service-manager`
- `scripts/bash/systemd-service-manager.sh`

打包后的单文件产物内嵌了 `init` 所需模板，因此把脚本单独复制到其他目录后，仍可直接执行 `init` 生成 `deploy/systemd/` 骨架。

## Test

```bash
pnpm run test:systemd-service-manager
```

## Quality Gate

```bash
pnpm run qa:systemd-service-manager
pnpm qa
```
