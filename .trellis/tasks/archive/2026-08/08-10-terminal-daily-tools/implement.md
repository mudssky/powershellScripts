# 实施计划

## 顺序清单

1. 开发前重新加载 `repo-ops` Shell Profile reference、Shell shared 与三平台安装规范。
2. 修改 `profile/installer/apps-config.json`：
   - macOS Core 加入 `zsh-autosuggestions`、`zsh-syntax-highlighting`、`git-delta`、`tealdeer`。
   - 将现有 Homebrew Dust 条目改为 macOS Core，命令修正为 `brew install dust`，删除 `skipInstall`。
   - Windows Core 新增 Scoop Main `delta`；现有未分层的 Scoop `tldr` 保持不选中。
   - Linux Full `terminal-extras` 新增 Homebrew `git-delta`、`tealdeer`，Linux Core 排除。
   - 插件使用 Homebrew formula 检测；CLI 分别使用 `delta`、`tldr`、`dust` 检测。
3. 新增 `shell/zsh.d/95-zsh-autosuggestions.zsh`：交互式 Zsh 守卫、Homebrew 前缀查找、重复 source 守卫、失败安静降级。
4. 新增 `shell/zsh.d/zzz-zsh-syntax-highlighting.zsh`：同样的发现/降级合同，并通过文件名字典序保证最后加载。
5. 扩展 `scripts/bash/tests/shell-tool-integration.test.ts` 或同包专属测试：观察插件 source 顺序、幂等、失败隔离、Atuin `Ctrl+r`、Up 保持和插件运行标记。
6. 扩展 `tests/MacOSInstallPipeline.Tests.ps1`、`tests/WindowsInstallPipeline.Tests.ps1`、`tests/LinuxInstallPipeline.Tests.ps1` 与 `psutils/tests/install.Tests.ps1`：锁定三平台选择、Homebrew formula 检测和 Dust 修复。
7. 更新 `docs/install/README.md`、`repo-ops` Shell Profile reference 与三平台 Trellis 安装规范；不创建不存在的平台 README。
8. 先运行窄测与语法检查；通过后在当前 macOS 使用 Homebrew 安装五项并运行 `./shell/deploy.sh --shell zsh`。
9. 从新交互式 Zsh 执行真实 smoke：插件 widget/函数、Atuin 键位、Carapace/Atuin/Starship、Delta TTY 守卫、TLDR 页面、Dust alias。
10. 对 Windows/Linux 运行安装 Preview 与只读选择验证；不在当前 macOS 伪装真实 Windows/WSL 安装。
11. 执行仓库强制门禁；失败时修复源头，不放宽行为断言。
12. Smoke 成功后最后清理临时 fixture、重复说明和无用变量，再按功能分批提交并归档任务。

## 验证命令

```bash
# Shell 语法与包级行为
zsh -n shell/zsh.d/95-zsh-autosuggestions.zsh shell/zsh.d/zzz-zsh-syntax-highlighting.zsh
bash -n shell/deploy.sh shell/shared.d/git-delta.sh shell/shared.d/aliases.sh
pnpm test:bash

# 三平台安装选择与 formula 检测
pwsh -NoProfile -NoLogo -Command "$env:PWSH_TEST_PATH='tests/MacOSInstallPipeline.Tests.ps1;tests/WindowsInstallPipeline.Tests.ps1;tests/LinuxInstallPipeline.Tests.ps1;psutils/tests/install.Tests.ps1'; $env:PWSH_TEST_MODE='serial'; $c=./PesterConfiguration.ps1; $c.Run.Exit=$true; Invoke-Pester -Configuration $c"
pwsh -NoProfile -NoLogo -File ./macos/05installCoreCli.ps1 -WhatIf
pwsh -NoProfile -NoLogo -File ./windows/05installCoreCli.ps1 -WhatIf
pwsh -NoProfile -NoLogo -File ./linux/05installCoreCli.ps1 -WhatIf
pwsh -NoProfile -NoLogo -File ./linux/08installFullApps.ps1 -WhatIf
pwsh -NoProfile -NoLogo -File ./macos/pwsh/Test-InstallState.ps1 -Step core-cli -OutputFormat Json

# 本机安装与部署（规划批准后）
brew install zsh-autosuggestions zsh-syntax-highlighting git-delta tealdeer dust
./shell/deploy.sh --shell zsh --dry-run
./shell/deploy.sh --shell zsh
tldr --update

# 版本与真实 Zsh smoke
delta --version
tldr --version
dust --version
zsh -lic 'typeset -f _zsh_autosuggest_start >/dev/null; typeset -f _zsh_highlight >/dev/null; bindkey "^R"; printf "carapace=%s atuin=%s\n" "${__CarapaceInitialized:-0}" "${__AtuinInitialized:-0}"'
tldr git

# 项目强制门禁
pnpm test:pwsh:all
pnpm qa
git diff --check
```

若 Docker 不可用，按仓库规则至少执行 `pnpm test:pwsh:full`，并明确 Linux coverage 依赖 CI 或 WSL。

## 高风险文件与检查点

- `profile/installer/apps-config.json`：软件真源；重点检查 macOS Core、Windows Core 与 Linux Full 的选择矩阵、无重复条目、插件 formula 检测和 Dust 失效命令清理。
- `shell/zsh.d/95-zsh-autosuggestions.zsh`：必须在 Atuin 后加载，不能接管 `Ctrl+r` 或 Up。
- `shell/zsh.d/zzz-zsh-syntax-highlighting.zsh`：必须是最终 Zsh 插件，不得阻断 prompt 或其它 widget。
- `scripts/bash/tests/**`：测试运行态标记/widget，不用源码字符串代替行为验证。
- `tests/*InstallPipeline.Tests.ps1`：Windows Core 精确 13 项、Linux Core/Full 边界和 macOS formula 检测必须同时锁定。
- 用户 `~/.zshrc` 与 `~/.bashrc.d/`：只通过现有部署器修改；部署器按既有规则备份 rc 并管理 symlink。

## 回滚点

- 删除两个 Zsh 片段并重新运行 `shell/deploy.sh --shell zsh`，部署器清理失效 symlink。
- 从 Windows/macOS Core 与 Linux Full 清单移除 Delta，移除 macOS/Linux Tealdeer，并恢复 Dust 条目；不会自动卸载本机软件。
- 本机如需卸载，单独执行 `brew uninstall zsh-autosuggestions zsh-syntax-highlighting git-delta tealdeer dust`，不作为仓库回滚自动步骤。

## 启动前检查

- PRD 已确认平台矩阵，无开放产品问题。
- `design.md`、`implement.md`、`implement.jsonl` 与 `check.jsonl` 一致。
- 用户已在本规划摘要之后明确批准实施。