# Linux 与 WSL 安装流水线规范

## Scenario: Ubuntu/Debian、Arch、WSL Stage 0、Core/Full 与只读验证

### 1. Scope / Trigger

- Trigger: 修改 `linux/00quickstart.sh`、编号 01～08、`linux/99verifyInstall.ps1`、`linux/pwsh/**`、`linux/wsl/wsl.conf`、Linux 系统包清单或根编排器中的 Linux 路径。
- Scope: Ubuntu/Debian、Arch 与 WSL 客体 amd64；ARM 只提供识别和 Blocked。
- Design intent: 根编排器拥有步骤图，Linux 叶子拥有 apt/pacman/Linuxbrew、平台能力、Docker 与 WSL 客体业务；软件清单和验证共享真源。

### 2. Signatures

```bash
bash linux/00quickstart.sh \
  [--repo-url <url>] [--repo-dir <path>] \
  [--preset Core|Full] [--network-mode Direct|China|Auto] \
  [--powershell-package <deb|tar.gz>] \
  [--unattended|--non-interactive] [--dry-run]

bash linux/03configureSources.sh \
  --network-mode Direct|China|Auto \
  [--transaction-id <id>] [--output-format Text|Json] [--dry-run]

bash linux/04deployShellConfig.sh \
  --preset Core|Full [--shell bash|zsh] [--dry-run]
```

```powershell
pwsh linux/05installCoreCli.ps1 -Preset Core|Full [-WhatIf]
pwsh linux/06installFonts.ps1 -Preset Core|Full -Environment Auto|Desktop|Server [-WhatIf]
pwsh linux/07installProfileTools.ps1 -Preset Core|Full [-WhatIf]
pwsh linux/08installFullApps.ps1 -Preset Full [-WhatIf]
pwsh linux/99verifyInstall.ps1 -Preset Core|Full [-Step <id[]>] [-OutputFormat Text|Json]
```

### 3. Contracts

- 00 使用 shallow clone；已有开发 clone 不 pull、不重写 history。获得 PowerShell 7 后必须移交根 Stage 1。
- 完整支持矩阵为 Ubuntu/Debian、Arch、WSL 客体、amd64。ARM/unknown 为 Blocked。
- Direct 允许官方 Stage 0 下载；China/Auto 在发行版前置或 PowerShell 未满足且无可恢复 adapter 时返回 10，不静默回退。
- Debian PowerShell 使用官方 deb；Arch 使用官方 `linux-x64.tar.gz` 并校验 SHA256。yay 是 `linux/arch/installYay.sh` 显式可选能力，不属于 Core。
- `config/install/linux-packages.psd1` 是 apt/pacman 系统包真源；`apps-config.json` 是 Linuxbrew CLI 真源。
- pacman 需要刷新索引时使用单次 `-Syu --needed` 完成同步升级与安装，不允许 `-Sy` 后分离执行 `-S` 形成部分升级。
- 03 组合发行版、brew、npm、pnpm、pip、go target，事务与 Auto Restore 由共享引擎和根编排器负责。
- 04 只调用 `shell/deploy.sh`；Linuxbrew PATH 由 `shell/shared.d/homebrew.sh` 从已知 prefix 恢复，不直接追加 rc。
- 05 选择 `Linux + core + cli`；08 选择 `Linux + cli + terminal-extras`，不安装 GUI。
- 06 Auto 在 WSL 和无桌面环境选择 Server，并以内部 Skipped 退出 0；Desktop 使用发行版字体包和 `fc-cache`。
- 07 复用共享 `ProfileTools.psm1`，Linux 只追加系统包、Docker 和 WSL 客体配置。
- Docker 以 `docker info` 判断实际可用性；已有 Docker Desktop/Engine 不重复安装。
- 客体 Engine 首次安装后若当前用户尚无 daemon 权限，07 将用户加入 `docker` 组、以 sudo 验证 daemon，并返回 10，要求重新登录或重启 WSL 后重跑。
- `wsl.conf` 内容未变化不备份；变化时备份并原子替换，返回 RestartRequired/10。客体入口不得执行 `wsl --shutdown`。
- 99 只读，JSON stdout 单文档；Failed/1 > Blocked/10 > Succeeded/0，Skipped/Warn 不单独改变退出码。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|---|---|
| `--unattended` 与 `--non-interactive` 同时使用 | 参数错误，退出 2 |
| Stage 0 非 Linux、非 Debian/Arch、非 amd64 | Blocked，退出 10 |
| China/Auto 缺 Git 或缺 pwsh 且无本地包 | Blocked，零系统包/下载写入 |
| 03 遇到未知发行版 target | Blocked，退出 10 |
| 05/08 WhatIf 且 brew 缺失 | 仍输出应用预览，不 Blocked |
| 06 Auto 在 WSLg | 默认 Server/Skipped；显式 Desktop 才安装 |
| `/etc/wsl.conf` 变化 | 备份、原子替换、返回 10，并提示宿主重启 |
| `docker` CLI 存在但 `docker info` 失败 | 视为未满足，不误报 AlreadyPresent |
| Docker Engine 已安装但当前会话尚未刷新 `docker` 组 | daemon 验证成功后返回 10，提示重新登录或重启 WSL |
| 99 `-OutputFormat Json` | stdout 可直接 `ConvertFrom-Json` |
| Arch amd64 验证 | 执行 pacman 清单的真实只读检查 |
| ARM 验证 | 结构化 Blocked，不误走 amd64 安装 |

### 5. Good / Base / Bad Cases

- Good: WSL 已由 Docker Desktop 提供可用 daemon，07 跳过客体 Engine 安装。
- Good: 普通 WSL Core 不安装字体，Windows Terminal 继续使用宿主字体。
- Base: WSL config 已部署但 systemd 尚未生效，07/99 返回 Blocked 并给出 `wsl --shutdown`。
- Bad: 叶子脚本内嵌清华/Aliyun URL、直接写 `.bashrc` 或调用 `get.docker.com --mirror`。
- Bad: 用 `command -v docker` 代替 `docker info` 判断 daemon 可用。

### 6. Tests Required

- Vitest：Stage 0 shallow clone、China/Auto Blocked、01/02 dry-run、03 参数透传、04 临时 HOME、Homebrew shell fragment。
- Pester：Ubuntu/Debian/WSL/Arch/ARM 平台模型，apt/pacman 分派，05/08 标签边界，06 环境选择，07 WhatIf，WSL config 幂等/备份，Docker Preview。
- Pester：99 单文档 JSON、精确步骤、未知步骤、清单名称来源、ARM Blocked 与 WSL systemd 状态。
- 回归：macOS 07 公共 Profile Tools 抽取后保持原测试通过。
- Gates：`pnpm test:bash`、`pnpm qa`、`pnpm test:pwsh:all`、`git diff --check`。

### 7. Wrong vs Correct

#### Wrong

```bash
curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"' >> ~/.bashrc
```

#### Correct

```powershell
$available = Test-LinuxDockerAvailable
$apps = Invoke-LinuxBrewCatalogInstall `
    -RepoRoot $repoRoot `
    -RequiredTag @('core', 'cli') `
    -Preview:$WhatIfPreference
```

理由：系统包、source 与 shell 配置分别由声明式清单、事务引擎和受管片段拥有，叶子不散落不可恢复副作用。
