## 背景与现状
- 当前已有功能：`Set-DockerRegistryMirror` 已在 `start-container.ps1:253-284` 中实现镜像源写入 `daemon.json` 与重启（Linux 支持 `systemctl`），默认中国镜像在 `start-container.ps1:276`。
- 存在问题：切换镜像前未进行连通性/可用性测试，可能导致 Docker 无法拉取镜像；未形成通用的“系统/多软件换源”脚本入口；缺少备份与回滚能力的规范化流程。
- 现有调用入口：在主流程中通过 `-UseChinaMirror`/`-RegistryMirrors`/`-DisableMirror` 触发（`start-container.ps1:327-329`）。

## 目标与范围
- 新增通用换源脚本：`Switch-Mirrors.ps1`，统一为多个软件提供换源能力；首期专注于 Docker，后续扩展系统与其他包管理器。
- 首期目标（可交付）：
  - 在切换 Docker 镜像前对候选镜像进行“可达性+基本可用性”测试，择优选择。
  - 保留原配置，自动备份 `daemon.json`，支持 Dry-Run、安全回滚。
  - 跨平台路径与重启提示（Linux 自动重启，Win/macOS 输出指引）。
- 后续扩展（规划）：APT（Ubuntu/Debian）、Pacman（Arch）、Homebrew、PIP、NPM/Yarn/PNPM 等。

## 功能设计
- 入口命令：`Switch-Mirrors.ps1 -Target docker -MirrorUrls <string[]> [-UseChinaMirror] [-Disable] [-TimeoutSec <int>] [-Retry <int>] [-DryRun]`
- 辅助函数：
  - `Test-MirrorUrl`：并发/逐一对镜像进行可达性测试；Docker 镜像以 `HEAD/GET https://mirror/v2/` 为基准，认为 `200/401` 皆为有效（仓库要求认证时返回 401）。支持超时与重试、统计响应耗时。
  - `Select-BestMirror`：在通过测试的镜像中按「最短耗时」排序选择；支持回退策略（全部失效则保持原配置）。
  - `Get-DockerDaemonPath`：沿用并统一到新脚本；跨平台返回 `daemon.json` 路径。
  - `Set-DockerRegistryMirror`：在新脚本中重用/抽取，增加“写入前测试、备份、DryRun 预览、回滚开关”。
  - `Invoke-DockerRestart`：Linux 执行 `systemctl daemon-reload && systemctl restart docker`，其他平台输出指引。
- 安全性与健壮性：
  - 启用 `Set-StrictMode`、`$ErrorActionPreference = 'Stop'`；对每一步记录上下文（镜像 URL、耗时、状态码等）。
  - 备份策略：`daemon.json` 变更前生成 `daemon.json.bak.<timestamp>`；失败可自动回滚或提示人工恢复。
  - 幂等性：若配置未变化或无可用镜像则不写入。

## 与现有脚本的关系
- 独立新脚本用于换源；`start-container.ps1` 保持现状，仅在需要时可改为调用新脚本的函数以减少重复代码。
- 保留现有默认镜像地址（`start-container.ps1:276`），但改为“先验证再写入”。

## 验证方案
- Pester 单元测试：
  - `Test-MirrorUrl`：对已知可访问端点 `https://registry-1.docker.io/v2/` 验证返回码与超时处理；对不可达域名验证失败分支。
  - `Set-DockerRegistryMirror`（Dry-Run）：验证输出 JSON 结构包含 `registry-mirrors`，不写文件；备份逻辑在非 Dry-Run 路径模拟（可采用临时目录）。
- 冒烟测试：在 Linux 环境执行 `-UseChinaMirror -DryRun` 查看执行计划；执行非 Dry-Run 时验证 Docker 能正常拉取并在失败时回滚。

## 风险与回滚
- 风险：镜像源可达但仓库数据不完整；写入后 Docker 未能启动。
- 缓解：使用 `v2/` 探活与状态码策略；写入前备份、失败自动回滚；保留 `-Disable` 快速移除镜像源。

## 交付物
- 新增：`Switch-Mirrors.ps1`（完整生产级脚本，含 `.SYNOPSIS/.DESCRIPTION/.PARAMETER/.EXAMPLE` 注释）。
- 文档：在 `docs/` 添加使用说明与注意事项；脚本头部注释同步更新。
- 测试：新增 Pester 测试文件。

## 实施步骤
- Step 1（上下文确认）：复用 `Get-DockerDaemonPath` 与现有路径逻辑，梳理镜像源参数。
- Step 2（实现）：编写 `Test-MirrorUrl`、`Select-BestMirror`、`Set-DockerRegistryMirror`（含备份/回滚/重启/干运行）、入口参数解析。
- Step 3（验证）：添加 Pester 测试与冒烟脚本；在 Linux 上进行真实拉取验证。

## 后续计划（系统与多软件）
- APT：识别发行版代号（`lsb_release -cs`），镜像可用性通过 `GET https://mirror/dists/<codename>/InRelease`；写入前备份 `/etc/apt/sources.list`。
- Pacman：通过 `GET https://mirror/$repo/os/$arch/` 探活，更新 `/etc/pacman.d/mirrorlist`。
- Homebrew：替换 `HOMEBREW_BOTTLE_DOMAIN` 与源地址，探活 `GET <domain>/bottles/`。
- PIP/NPM：以 `pip config set`、`.npmrc` 写入镜像源；分别用 `GET` 探活对应仓库根路径。
