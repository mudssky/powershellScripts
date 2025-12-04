## 问题原因
- 测试文件硬编码了绝对路径 `c:\home\env\powershellScripts\profile\profile_unix.ps1` 与 `profile.ps1`，在 GitHub Actions 的工作目录（例如 `D:\a\powershellScripts\powershellScripts`）下不存在该路径，导致 `BeforeAll` 直接抛错。
- 两个性能基准的 `Describe` 在任意平台都会执行 `BeforeAll` 的存在性检查；虽然 `It` 里有按操作系统跳过逻辑，但 `BeforeAll` 的硬编码路径先失败。

## 修复方案
- 将测试中的绝对路径改为基于仓库相对路径的计算，使用 `$PSScriptRoot` 推导仓库根目录，再用 `Join-Path` 组合出 `profile` 文件位置。
- 保持现有的按操作系统跳过的逻辑不变，只修正路径来源，避免在不同 CI 工作目录下出错。

## 具体修改
- `psutils/tests/profile_unix.Tests.ps1`
  - 替换 `BeforeAll` 中的路径计算：
    ```powershell
    BeforeAll {
        $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:ProfilePath = Join-Path $RepoRoot 'profile' 'profile_unix.ps1'
        if (-not (Test-Path $script:ProfilePath)) {
            throw "Profile 文件不存在: $script:ProfilePath"
        }
    }
    ```
- `psutils/tests/profile_windows.Tests.ps1`
  - 替换 `BeforeAll` 中的路径计算：
    ```powershell
    BeforeAll {
        $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')).Path
        $script:ProfilePath = Join-Path $RepoRoot 'profile' 'profile.ps1'
        if (-not (Test-Path $script:ProfilePath)) {
            throw "Profile 文件不存在: $script:ProfilePath"
        }
    }
    ```
- 说明：`$PSScriptRoot` 指向当前测试文件所在目录 `psutils/tests`，向上两级即为仓库根；`Resolve-Path` 统一路径格式并消除相对路径。

## 验证步骤
- 本地与 CI：运行 `pnpm test`，确认：
  - Windows runner：`Windows Profile 性能基准` 的两个 `It` 正常执行；`Unix Profile 性能基准` 的 `BeforeAll` 通过，`It` 被按平台跳过。
  - Linux/macOS runner：相反逻辑生效。
- 断言覆盖率与其他测试保持稳定（当前报告约 25% 覆盖率不会因路径修复变化）。
- 如需额外稳健性，可在两处 `Test-Path` 前添加 `Write-Host` 打印实际解析出的路径，辅助排查 CI 变量差异（不影响断言）。

## 影响面分析
- 修改文件：`psutils/tests/profile_unix.Tests.ps1`、`psutils/tests/profile_windows.Tests.ps1`
- 风险：仅调整路径解析方式，不改变被测 Profile 行为；若未来移动测试目录结构，需要同步更新两级目录推导。

## 回滚方案
- 如 CI 仍失败，可暂时在 GitHub Actions 步骤中设置环境变量 `POWERSHELL_SCRIPTS_ROOT=$GITHUB_WORKSPACE` 并在 `BeforeAll` 使用该变量优先定位，否则再回退到 `$PSScriptRoot` 两级父目录推导。