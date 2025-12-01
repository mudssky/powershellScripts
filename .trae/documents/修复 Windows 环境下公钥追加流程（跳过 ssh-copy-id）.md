## 问题与目标
- 问题：在 Windows 下 `ssh-copy-id` 可能被 `Get-Command` 识别为 Application，但不可用或非标准实现，导致脚本尝试调用失败或行为不一致。
- 目标：在 Windows 环境下始终绕过 `ssh-copy-id`，采用更稳健的追加公钥方案；在 Linux/macOS 环境继续优先使用 `ssh-copy-id`，保持跨平台一致性与幂等。

## 方案改动
- OS 检测：使用 PowerShell 7+ 内置变量 `$IsWindows/$IsLinux/$IsMacOS` 判定平台。
- 调用策略：
  - Windows：无论 `Get-Command ssh-copy-id` 是否有结果，都跳过 `ssh-copy-id`，优先使用 `scp` 上传 `.pub` 到远端临时文件并 `cat >> authorized_keys`；若 `scp` 不存在，则采用管道方式将公钥内容通过 stdin 送到远端 `cat >> authorized_keys`。
  - Linux/macOS：优先 `ssh-copy-id`；若不可用，回退到 `scp`；再回退到管道方式。
- 管道追加实现（避免复杂引号转义）：
  - `Get-Content -Raw $pubPath | ssh -p $Port $login "umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys; chmod 600 ~/.ssh/authorized_keys"`
- 干跑输出（DryRun）：根据所选分支打印对应命令（`ssh-copy-id`/`scp`/管道），便于验证决策逻辑。
- 校验追加结果：沿用现有 `grep -F` 检查，若管道写入则同样匹配到公钥行。

## 具体改动点
- 位置：`Setup-SshNoPasswd.ps1`
  - 在选择分支处加入 `$IsWindows` 条件，强制 Windows 走 `scp`→管道回退，不调用 `ssh-copy-id`。
  - 新增管道回退实现与 DryRun 文案。
  - 保持现有权限修复、config 写入与验证逻辑不变。

## 验证
- Windows（DryRun）：输出应为 `scp` 或管道方案，不出现 `ssh-copy-id`；仍输出权限修复与 `~/.ssh/config` 写入计划。
- Linux/macOS（DryRun）：若系统存在 `ssh-copy-id`，显示其调用；否则显示 `scp` 或管道方案。
- 实测：对一台可用远端执行非 DryRun，确认授权成功且可用别名连接。

## 风险与缓解
- 引号/换行转义：管道方式避免在远端命令中嵌入公钥文本，降低崩溃风险。
- `scp/ssh` 缺失：已加入回退链路；若客户端完全缺失 OpenSSH，将在依赖检测阶段明确报错。

## Plan
- [ ] Impact Analysis：仅更新 `Setup-SshNoPasswd.ps1` 追加 Windows 分支逻辑与管道回退；文档无需大改，仅可选补充一句“Windows 将跳过 ssh-copy-id”。
- [ ] Step 1: Context Gathering：确认 `$IsWindows` 可用，现有 `scp`/管道分支接口稳定。
- [ ] Step 2: Implementation：按上述策略更新分支与 DryRun 输出。
- [ ] Step 3: Verification：在 Windows 环境运行 DryRun，确保不出现 `ssh-copy-id`；必要时再对 Linux/macOS DryRun 验证；提供一台远端进行实际授权测试。

请确认方案，确认后我将实施修改并进行 DryRun 与实际验证。