# Implement — WSL 内调用 browser-debug 创建 Windows 快捷方式与启动

## 执行清单（按序）

1. **runtime.ps1 UNC Bypass 分支**
   - `scripts/pwsh/devops/browser-debug/runtime.ps1` `New-BrowserDebugShortcut`：`$entryPath` 以 `\\` 开头时参数插入 `-ExecutionPolicy Bypass`；本地路径不变。
   - 新增/更新测试 `tests/BrowserDebugProfile.Tests.ps1`：UNC 入口路径断言参数含 `-ExecutionPolicy Bypass`；本地路径断言不含（回归锚点）。

2. **shell 片段**
   - 新增 `shell/shared.d/browser-debug.sh`：交互式判断 → pwsh 探测（D1 顺序）→ repo 根解析（D2 优先级）→ `wslpath -w` 转换 → 入口存在性校验 → 注册 `browser-debug()` 函数；任一步失败安静返回；会话标记防重复注册。
   - 函数内按 D6 对绝对 POSIX 路径参数做 `wslpath -w` 转换后透传。
   - 遵守 `.agents/skills/repo-ops/references/shell-profile-integration.md` 的降级与幂等合同。

3. **repo-ops reference**
   - 新增 `.agents/skills/repo-ops/references/wsl-windows-interop.md`：直调契约、Bypass 必要性、pwsh 7 硬依赖、CDP 直连（mirrored + hostAddressLoopback）、命令树与验证命令。
   - `.agents/skills/repo-ops/SKILL.md` 工作流清单追加一条指向该 reference 的路由（匹配 WSL 调用请求时必读）。

4. **文档索引**
   - `docs/scripts-index.md` browser-debug 区块补充 WSL 调用方式（一行 + 指向 repo-ops reference 或函数说明）。

5. **部署与真实验证**
   - `shell/deploy.sh` 同步新片段到 `~/.bashrc.d/`；新开 zsh 验证注册与降级。
   - 端到端（PRD R5，最终验收）：WSL 内 `browser-debug profile create <验收用名> --browser chrome` → 确认桌面 `.lnk` 与 registry 登记 → `profile start` → WSL 内 `curl http://localhost:<cdpPort>/json/version` 返回 CDP 信息 → 双击快捷方式复验启动 → 验证完成后询问用户是否保留该 Profile（复制自真实 Chrome 数据，删除属破坏性操作，不自动清理）。

## 验证命令

```bash
# shell 语法
bash -n shell/shared.d/browser-debug.sh && zsh -n shell/shared.d/browser-debug.sh

# shell 测试（含 shared.d fixture 的 vitest 套件）
pnpm qa:bash

# pwsh 窄测 → 全量（AGENTS.md 门禁）
pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode serial   # 或含 BrowserDebug 的最小路径
pnpm test:pwsh:all

# 根质量门禁
pnpm qa

# WSL 真实链路 smoke（需 interop，只读命令）
zsh -ic 'browser-debug profile list; echo exit=$?'
zsh -ic 'browser-debug help' 
"/mnt/c/Program Files/PowerShell/7/pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w bin/browser-debug.ps1)" profile list
```

## 风险文件与回滚点

- `scripts/pwsh/devops/browser-debug/runtime.ps1`：唯一业务行为变更点，独立 commit，可单独 revert。
- `shell/shared.d/browser-debug.sh`：新增文件，删除即回滚。
- `tests/BrowserDebugProfile.Tests.ps1`：仅追加断言，不动既有用例。

## task.py start 前检查

- [ ] prd.md 已通过收敛（无遗留 Open Questions、无重复事实）。
- [ ] 用户已明确批准最终规划摘要。
- [ ] 实施环境具备：WSL interop + Windows pwsh 7（已实测可用）。
