# 实施计划

## 顺序清单

1. 将当前未完成草稿干净迁移为 `.agents/skills/repo-ops/`。
   - 主入口为 `SKILL.md`，只承担仓库操作路由和通用事实/验证边界。
   - 当前 Shell Profile 流程写入 `references/shell-profile-integration.md`，加入安装清单、平台选择、Scoop bucket 前置和验证合同。
   - 删除旧 `.agents/skills/powershellscripts-shell-profile/` 路径，不保留 alias 或重复入口。
   - 对照现有 Skill 做触发冲突、自包含与行为增益检查。
2. 用 `repo-ops` 的 Shell Profile reference 重新读取本任务 PRD/设计与相关规范，确认后再修改产品代码。
3. 修改 `profile/installer/apps-config.json`。
   - Windows Core：Scoop `atuin`、Extras `carapace-bin`。
   - macOS Core：Homebrew `atuin`、`carapace`。
   - Linux Full：Homebrew `atuin`、`carapace`，标签为 `cli + terminal-extras`；Linux Core 排除。
4. 扩展 `windows/pwsh/WindowsInstall.psm1` 与应用清单校验。
   - 抽取通用 `Initialize-WindowsScoopBucket`，让字体与应用 catalog 共用；从选择结果提取 `bucket`，幂等确保 Extras bucket。
   - 校验 `bucket` 仅用于 Scoop、值非空且格式合法；覆盖 Preview、失败停止与已存在路径。
5. 新增 `shell/shared.d/10-carapace.sh`。
   - 交互式守护、命令守护、Bash/Zsh 分流、重复 source 守卫。
6. 新增 `shell/shared.d/90-atuin.sh`。
   - 交互式守护、命令守护、`--disable-up-arrow`、重复 hooks 守卫。
7. 修改 `profile/features/environment.ps1`。
   - 扩展批量命令探测。
   - 增加 Carapace/Atuin 缓存初始化与会话状态。
   - 保持缺失工具不进入 Profile 安装提示。
8. 修改 `profile/core/loadModule.ps1`。
   - 根据 Carapace 初始化状态选择 `MenuComplete` 或 `Complete`。
   - 保持 OnIdle 单订阅与每项错误隔离。
9. 增加 Shell Vitest、PowerShell Pester、安装目录选择与 Scoop bucket 行为测试。
10. 更新 `.trellis/spec/infra/windows-install-pipeline.md` 的 Windows Core 精确集合为 12 项，并记录通用 Scoop bucket 合同；macOS/Linux 规范只需在与实现不一致时同步。
11. 更新 `profile/README.md`、平台安装文档和 Skill，确保命令、键位、安装预设、缓存、降级与部署路径一致。
12. 执行验证；失败时修源头，不放宽断言或静默吞错。
13. 最后执行清理：删除重复说明、无用变量、临时 fixture 与失效缓存测试产物。

## 验证命令

```bash
# Skill 结构审计
python3 skill://skill-dev-guidelines/scripts/audit_skill.py .agents/skills/repo-ops --strict

# Bash/Zsh 语法与 fixture source smoke
bash -n shell/shared.d/10-carapace.sh shell/shared.d/90-atuin.sh
zsh -n shell/shared.d/10-carapace.sh shell/shared.d/90-atuin.sh
pnpm --filter bash-scripts test:bash

# 安装选择与 PowerShell Profile 窄测
pwsh -NoProfile -NoLogo -Command "$env:PWSH_TEST_PATH='tests/WindowsInstallPipeline.Tests.ps1;tests/MacOSInstallPipeline.Tests.ps1;tests/LinuxInstallPipeline.Tests.ps1;tests/ProfileInstallHints.Tests.ps1;tests/ProfileLoading.Tests.ps1'; $env:PWSH_TEST_MODE='serial'; $c=./PesterConfiguration.ps1; $c.Run.Exit=$true; Invoke-Pester -Configuration $c"

# 三平台安装预览
pwsh -NoProfile -NoLogo -File ./windows/05installCoreCli.ps1 -WhatIf
pwsh -NoProfile -NoLogo -File ./macos/05installCoreCli.ps1 -WhatIf
pwsh -NoProfile -NoLogo -File ./linux/05installCoreCli.ps1 -WhatIf
pwsh -NoProfile -NoLogo -File ./linux/08installFullApps.ps1 -WhatIf

# Profile 真实入口与项目强制门禁
pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1 -Mode Full -Iterations 3
pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1 -Mode Minimal -Iterations 2
pnpm test:pwsh:all
pnpm qa
```

若 Docker 不可用，按仓库规则至少执行 `pnpm test:pwsh:full`，并明确 Linux coverage 依赖 CI 或 WSL。

## 高风险文件与检查点

- `profile/installer/apps-config.json`：唯一软件清单；重点检查 OS 与 Core/terminal-extras 选择矩阵。
- `windows/pwsh/WindowsInstall.psm1` 与 `psutils/modules/install.psm1`：通用 Scoop bucket 与清单校验；重点检查 bucket 幂等、Preview、失败停止及 nerd-fonts 回归。
- `profile/features/environment.ps1`：同步 Full 启动路径；重点检查外部进程次数、缓存、缺失工具降级。
- `profile/core/loadModule.ps1`：共享 OnIdle 生命周期；重点检查重复订阅与 Tab 回退。
- `.agents/skills/repo-ops/**`：项目本地资产；重点检查主入口精简、reference 可达、旧路径已清理，且不得写入 bundled Trellis Skill 目录。
- `shell/shared.d/10-carapace.sh`：必须位于 Zsh compinit 后、命令专属 completion 前。
- `shell/shared.d/90-atuin.sh`：必须避免重复 preexec/precmd hooks。

## 回滚点

- Skill 回滚为恢复到任务开始前不存在该 Skill 的状态；不保留旧名或转发入口，不影响运行态。
- Shell 配置回滚为删除两个片段并重新运行 `shell/deploy.sh`；部署脚本会清理失效 symlink。
- PowerShell 回滚为移除两个工具初始化项并恢复 Tab=`Complete`；现有 Starship/Zoxide/Fzf 行为保持不变。
- 安装回滚为移除 6 条 Carapace/Atuin 平台清单条目及 Scoop `bucket` 通用支持；不会卸载用户机器上已经安装的工具。

## 启动前检查

- PRD 无开放问题。
- `design.md` 与本计划一致。
- `implement.jsonl` / `check.jsonl` 已加入真实 spec 与调研条目。
- 用户已在最新最终规划摘要之后明确批准实施。
