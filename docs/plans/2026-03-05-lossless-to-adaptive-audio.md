# LosslessToAdaptiveAudio Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 在 `qaac.exe` 不存在时自动使用 `ffmpeg libopus`（`-b:a 256k`）编码并输出 `.ogg`，同时将脚本重命名为 `losslessToAdaptiveAudio.ps1`。

**Architecture:** 采用启动阶段一次性选择编码策略（`qaac` 或 `ffmpeg-opus`），并通过 `$using:` 传入并行块。保持现有并行、删除与 `WhatIf` 语义，新增可测试的函数拆分，避免直接依赖真实编码器做单元测试。

**Tech Stack:** PowerShell 7, Pester, ffmpeg, qaac, pnpm QA (`pnpm qa`)

---

### Task 1: 建立可测试骨架并添加失败测试

**Files:**
- Create: `tests/losslessToAdaptiveAudio.Tests.ps1`
- Modify: `scripts/pwsh/misc/losslessToQaac.ps1`

**Step 1: Write the failing test**

```powershell
Import-Module Pester -ErrorAction SilentlyContinue

Describe 'losslessToAdaptiveAudio encoder selection' {
    BeforeAll {
        $scriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'pwsh' 'misc' 'losslessToQaac.ps1'
        . (Resolve-Path $scriptPath)
    }

    It 'qaac 可用时选择 qaac' {
        Mock -CommandName Get-Command -MockWith {
            param([string]$Name)
            if ($Name -eq 'qaac.exe') { return @{ Name = 'qaac.exe' } }
            return $null
        }

        (Resolve-EncoderMode) | Should -Be 'qaac'
    }

    It 'qaac 不可用且 ffmpeg 可用时选择 ffmpeg-opus' {
        Mock -CommandName Get-Command -MockWith {
            param([string]$Name)
            if ($Name -eq 'ffmpeg') { return @{ Name = 'ffmpeg' } }
            return $null
        }

        (Resolve-EncoderMode) | Should -Be 'ffmpeg-opus'
    }

    It 'ffmpeg-opus 模式输出扩展名为 .ogg' {
        (Get-OutputExtension -EncoderMode 'ffmpeg-opus') | Should -Be '.ogg'
    }
}
```

**Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -Command "$env:PWSH_TEST_MODE='serial'; $env:PWSH_TEST_PATH='./tests/losslessToAdaptiveAudio.Tests.ps1'; Invoke-Pester -Configuration ( ./PesterConfiguration.ps1 )"`
Expected: FAIL，提示 `Resolve-EncoderMode` / `Get-OutputExtension` 未定义。

**Step 3: Write minimal implementation**

```powershell
function Resolve-EncoderMode {
    if (Get-Command 'qaac.exe' -ErrorAction SilentlyContinue) { return 'qaac' }
    if (Get-Command 'ffmpeg' -ErrorAction SilentlyContinue) { return 'ffmpeg-opus' }
    throw 'Neither qaac.exe nor ffmpeg was found in PATH.'
}

function Get-OutputExtension {
    param([string]$EncoderMode)
    if ($EncoderMode -eq 'ffmpeg-opus') { return '.ogg' }
    return '.m4a'
}
```

**Step 4: Run test to verify it passes**

Run: `pwsh -NoProfile -Command "$env:PWSH_TEST_MODE='serial'; $env:PWSH_TEST_PATH='./tests/losslessToAdaptiveAudio.Tests.ps1'; Invoke-Pester -Configuration ( ./PesterConfiguration.ps1 )"`
Expected: PASS。

**Step 5: Commit**

```bash
git add tests/losslessToAdaptiveAudio.Tests.ps1 scripts/pwsh/misc/losslessToQaac.ps1
git commit -m "test(audio): add encoder selection coverage"
```

### Task 2: 实现回退编码命令与输出路径切换

**Files:**
- Modify: `scripts/pwsh/misc/losslessToQaac.ps1`
- Test: `tests/losslessToAdaptiveAudio.Tests.ps1`

**Step 1: Write the failing test**

```powershell
It 'ffmpeg-opus 命令包含 libopus 与 256k 参数' {
    $cmd = New-EncodeCommand -EncoderMode 'ffmpeg-opus' -InputPath 'C:\a.flac' -OutputPath 'C:\a.ogg' -QaacParam '--verbose'
    $cmd | Should -Match '-c:a libopus'
    $cmd | Should -Match '-b:a 256k'
}

It 'qaac 命令仍然包含 qaac.exe 与 -o' {
    $cmd = New-EncodeCommand -EncoderMode 'qaac' -InputPath 'C:\a.flac' -OutputPath 'C:\a.m4a' -QaacParam '--verbose --rate keep -v320 -q2 --copy-artwork'
    $cmd | Should -Match '^qaac\.exe'
    $cmd | Should -Match " -o "
}
```

**Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -Command "$env:PWSH_TEST_MODE='serial'; $env:PWSH_TEST_PATH='./tests/losslessToAdaptiveAudio.Tests.ps1'; Invoke-Pester -Configuration ( ./PesterConfiguration.ps1 )"`
Expected: FAIL，提示 `New-EncodeCommand` 未定义。

**Step 3: Write minimal implementation**

```powershell
function New-EncodeCommand {
    param(
        [string]$EncoderMode,
        [string]$InputPath,
        [string]$OutputPath,
        [string]$QaacParam
    )

    if ($EncoderMode -eq 'ffmpeg-opus') {
        return "ffmpeg -y -i '$InputPath' -c:a libopus -b:a 256k '$OutputPath' > `$null 2>`$null"
    }

    return "qaac.exe $QaacParam '$InputPath' -o '$OutputPath' > `$null 2>`$null"
}
```

并将主流程改为：
- 启动时调用 `Resolve-EncoderMode`。
- 通过 `Get-OutputExtension` 生成输出后缀。
- 并行块中统一调用 `New-EncodeCommand`。
- 当模式为 `ffmpeg-opus` 且传入 `-he`，打印一次忽略提示。

**Step 4: Run test to verify it passes**

Run: `pwsh -NoProfile -Command "$env:PWSH_TEST_MODE='serial'; $env:PWSH_TEST_PATH='./tests/losslessToAdaptiveAudio.Tests.ps1'; Invoke-Pester -Configuration ( ./PesterConfiguration.ps1 )"`
Expected: PASS。

**Step 5: Commit**

```bash
git add tests/losslessToAdaptiveAudio.Tests.ps1 scripts/pwsh/misc/losslessToQaac.ps1
git commit -m "feat(audio): add ffmpeg opus fallback when qaac missing"
```

### Task 3: 重命名脚本并修正文档引用

**Files:**
- Move: `scripts/pwsh/misc/losslessToQaac.ps1` -> `scripts/pwsh/misc/losslessToAdaptiveAudio.ps1`
- Modify: `README.md`
- Modify: `QWEN.md`
- Modify: `docs/scripts-index.md`
- Modify: `tests/losslessToAdaptiveAudio.Tests.ps1`

**Step 1: Write the failing test**

```powershell
It '新脚本路径存在' {
    Test-Path -LiteralPath (Join-Path $PSScriptRoot '..' 'scripts' 'pwsh' 'misc' 'losslessToAdaptiveAudio.ps1') | Should -BeTrue
}
```

**Step 2: Run test to verify it fails**

Run: `pwsh -NoProfile -Command "$env:PWSH_TEST_MODE='serial'; $env:PWSH_TEST_PATH='./tests/losslessToAdaptiveAudio.Tests.ps1'; Invoke-Pester -Configuration ( ./PesterConfiguration.ps1 )"`
Expected: FAIL，新路径尚不存在。

**Step 3: Write minimal implementation**

```bash
git mv scripts/pwsh/misc/losslessToQaac.ps1 scripts/pwsh/misc/losslessToAdaptiveAudio.ps1
```

并更新以上文档中的脚本名与示例命令。

**Step 4: Run test to verify it passes**

Run: `pwsh -NoProfile -Command "$env:PWSH_TEST_MODE='serial'; $env:PWSH_TEST_PATH='./tests/losslessToAdaptiveAudio.Tests.ps1'; Invoke-Pester -Configuration ( ./PesterConfiguration.ps1 )"`
Expected: PASS。

**Step 5: Commit**

```bash
git add scripts/pwsh/misc/losslessToAdaptiveAudio.ps1 README.md QWEN.md docs/scripts-index.md tests/losslessToAdaptiveAudio.Tests.ps1
git commit -m "refactor(audio): rename script to losslessToAdaptiveAudio"
```

### Task 4: 端到端验证与 QA 收尾

**Files:**
- Modify (if needed): `scripts/pwsh/misc/losslessToAdaptiveAudio.ps1`
- Modify (if needed): `tests/losslessToAdaptiveAudio.Tests.ps1`

**Step 1: Write the failing test**

```powershell
It 'WhatIf 模式不应删除源文件（通过命令预演日志验证）' {
    # 根据当前测试基础设施，先写为 Pending，后续可替换为集成测试
    Set-ItResult -Skipped -Because '集成测试将在临时目录中补充'
}
```

**Step 2: Run tests to verify current status**

Run: `pnpm test:fast`
Expected: 全部通过（或仅预期 Skip）。

**Step 3: Run project QA (required by repository rule)**

Run: `pnpm qa`
Expected: 通过；若失败，按输出修复后重跑直至通过。

**Step 4: Final commit**

```bash
git add -A
git commit -m "chore(audio): finalize adaptive encoder migration with qa"
```

**Step 5: Verify final diff**

Run: `git log --oneline -n 5`
Expected: 最近提交包含测试、功能、重命名、QA 收尾。
