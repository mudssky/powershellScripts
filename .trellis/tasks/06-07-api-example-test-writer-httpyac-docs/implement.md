# 完善 api-example-test-writer httpyac 文档与示例 - Implementation Plan

## Checklist

- [x] 读取实施前上下文：
  - `trellis-before-dev`
  - `.trellis/spec/infra/agent-skill-dev.md`
  - 目标 skill 当前 `SKILL.md`、`references/`、`examples/`
- [x] 更新 `SKILL.md`：
  - 默认目录约定改为 `http/env/.env.example`、`http/env/.env.test`、`http/env/.env.local`。
  - 配置与认证规则改为新命名。
  - 资源路由增加 env 模板示例位置。
- [x] 更新 `references/httpyac-patterns.md`：
  - 环境文件章节改为 `.env.example`、`.env.test`、`.env.local`。
  - 增加 `.gitignore` 示例。
  - 强化登录取 token 后给受保护接口复用的完整案例。
  - 增加跨文件 `@import` 复用认证请求的说明。
  - CLI 命令覆盖 `--env test`、`--var`、`--tag`、`--json`、`--junit`、`--bail`。
- [x] 更新 `references/directory-structure.md`：
  - 小/中/大型目录树改为新 env 命名。
  - env/dotenv 配置、VS Code settings、CLI 命令和 `.gitignore` 统一新命名。
  - 保留 `http-client.env.json` 兼容提示。
- [x] 更新示例：
  - `examples/httpyac/auth-smoke.http` 去掉文件头硬编码 `@baseUrl`，依赖 env 变量。
  - `examples/httpyac/async-task.http` 去掉文件头硬编码 `@baseUrl`，必要时补 `# @import ./auth-smoke.http` / `# @ref login` 的认证复用示例。
  - 新增 `examples/httpyac/env/.env.example`。
  - 新增 `examples/httpyac/env/.env.test`。
  - 不新增真实 `.env.local`，仅在文档中展示占位内容。
- [x] 全局一致性检查：
  - 搜索旧默认 `dev.env.example`、`test.env.example`、`local.env`，确认只在兼容说明中出现。
  - 搜索 `.env.local` 相关 `.gitignore` 示例，确认不会忽略 `.env.example` / `.env.test`。
  - 检查 `.http` 请求块仍有面向人的注释。
- [x] 同步安装态 skill：
  - 优先执行 `pwsh -File ai/skills/Install-Skills.ps1 -Name api-example-test-writer -Agent codex -Yes -Force`。
  - 如安装命令失败，记录原因并说明手工同步方式。
- [x] 验证：
  - `rg -n "dev\\.env\\.example|test\\.env\\.example|local\\.env" ai/skills/dev/api-example-test-writer`
  - `rg -n "\\.env\\.example|\\.env\\.test|\\.env\\.local|envDirName|@ref login|@import|--env test|--var" ai/skills/dev/api-example-test-writer`
  - `find ai/skills/dev/api-example-test-writer/examples/httpyac -maxdepth 3 -type f | sort`
  - `git diff --check`
  - 如果只修改 Markdown、`.http` 和 `.env.example` 风格示例，不执行根目录 `pnpm qa`，并在最终说明原因。

## Risky Files / Rollback Points

- `SKILL.md` 是入口，必须保持短，不把 reference 内容整段搬入。
- `references/httpyac-patterns.md` 和 `references/directory-structure.md` 容易出现 env 命名不一致，必须用 `rg` 检查。
- `examples/httpyac/*.http` 不能破坏 httpyac 元数据、`@name`、`@tag`、`@ref` 和断言语法。
- 安装态同步会改动 `~/.agents/skills/api-example-test-writer`，如失败不应回滚仓库开发态改动。

## Validation Notes

本任务是文档与示例调整，不新增可执行业务代码。按项目规则，若最终只修改 Markdown、`.http` 和可提交 env 示例，不需要执行根目录 `pnpm qa`。
