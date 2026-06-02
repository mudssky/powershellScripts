# 整理根目录结构实施清单

## Ordered Checklist

- [x] 启动任务前读取根目录与相关 spec，避免碰到无关未提交改动。
- [x] 将根目录 `.mcp.json` 移动到 `ai/mcp/` 下，并更新仓库内旧路径引用。
- [x] 将 `blockDanmuku` 移到 `config/danmaku/block-danmuku.txt`。
- [x] 从仓库跟踪中移除 `.serena/`，删除禁用的 serena MCP 配置，并在 `.gitignore` 中忽略该目录。
- [x] 在 `.gitignore` 中增加 `.shrimp-data/`、`.playwright/` 等本地数据/缓存规则。
- [x] 重排 `.gitignore`，按类别分块并添加中文注释。
- [x] 保持 `ipynb/` 不变。
- [x] 将用户已搬迁的 `todos/` 纳入提交范围，并同步旧路径引用到 `docs/todos/`。
- [x] 复查 `git status --short`，确认没有混入用户已有无关改动。

## Validation Commands

- `rg -n --hidden --glob '!node_modules/**' --glob '!.git/**' '\\.mcp\\.json|blockDanmuku|\\.serena' .`
- `git status --short`
- 若只移动配置/文档并整理 ignore，不强制执行 `pnpm qa`；若实施中改到脚本逻辑，则执行 `pnpm qa`。

## Risk Points

- `.serena/` 当前是已跟踪目录，删除会产生多文件删除 diff；需要确认这是预期。
- `.mcp.json` 旧路径可能被外部工具隐式读取；本轮按用户决策不保留根目录副本。
- `blockDanmuku` 若被外部播放器硬编码读取，移动后需要用户同步外部工具路径。
