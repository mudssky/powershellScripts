# macOS mpv 平台配置拆分实施计划

## Checklist

- [x] 更新 PRD，记录平台拆分范围和验收标准。
- [x] 修改 `mpv.conf`：移除 Windows 专用配置，改为从 mpv 配置目录 include 本地覆盖。
- [x] 修改 `install.ps1`：新增平台默认 `mpv_local.conf` 生成逻辑。
- [x] 修改 `install.ps1`：macOS 生成 Finder 可识别的 `~/Applications/mpv.app` 外壳。
- [x] 更新 README：说明 Finder “打开方式”关联方法。
- [x] 为当前本机空 `mpv_local.conf` 生成 macOS 默认覆盖，并按要求备份。
- [x] 验证 `mpv --version` 不再因配置报错。
- [x] 执行根目录 `pnpm qa`；如 pwsh 相关验证要求触发，再执行 `pnpm test:pwsh:all` 或说明环境限制。

## Validation Commands

- `pwsh -NoProfile -File ./config/software/mpv/install.ps1 -Check`
- `mpv --version`
- `pnpm qa`
- `pnpm test:pwsh:all`

## Risky Files and Rollback Points

- `config/software/mpv/mpv.conf`：影响所有平台 mpv 启动配置。
- `config/software/mpv/install.ps1`：影响安装和本地配置初始化。
- `config/software/mpv/mpv_local.conf`：本机忽略文件，修改前必须备份。

## Follow-up Checks

- 确认 macOS 下 `mpv --version` 不输出 `d3d11`、`wasapi` 或 include 失败。
- 确认非空 `mpv_local.conf` 不会被安装脚本覆盖。

## Validation Results

- `pwsh -NoProfile -File ./config/software/mpv/install.ps1 -Check`：通过，输出 `True`。
- `mpv --version`：通过，不再输出 `d3d11`、`wasapi` 或 `mpv_local.conf` include 错误。
- PowerShell 语法解析：通过。
- `pnpm qa`：通过。
- `pnpm test:pwsh:full:assertions`：通过，594 passed / 0 failed / 4 skipped / 24 not run。
- `pnpm test:pwsh:all`：已尝试；宿主侧最初因 Pester 未安装失败，安装 Pester 后宿主侧通过；Linux Docker 侧因本机没有 `docker` 命令无法运行。
- `open -a "$HOME/Applications/mpv.app" <test-video>`：通过，实际启动 `/opt/homebrew/bin/mpv -- <test-video>`。
