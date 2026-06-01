# 改进 database-query 配置命令 Implement

## Checklist

- [x] 确认 `config` 子命令形态与输出字段。
- [x] 在 `config.ts` 导出配置查找元信息需要的函数或常量，保持不泄密。
- [x] 在 `cli.ts` 新增 `config` 子命令及其子动作。
- [x] 抽出底层客户端探测函数，支持原生命令和 WSL 可调用的 `.exe` 命令。
- [x] 更新 `doctor` 输出，区分 native、windows-exe、missing。
- [x] 增加 CLI 测试覆盖：
  - [x] `context` 默认仍为 text。
  - [x] `context --format json` 兼容。
  - [x] 配置路径命令输出 XDG/全局路径。
  - [x] 当前配置命令能识别显式配置与默认命中。
  - [x] `doctor` 能在原生命令缺失但 `.exe` 可用时报告可用。
  - [x] `doctor` 对原生命令和 `.exe` 都缺失时报告 missing。
- [x] 更新 `SKILL.md` 与 `references/skill-installation.md`。
- [x] 执行 `pnpm --dir ai/skills/dev/database-query check`。
- [x] 按项目根目录要求执行 `pnpm qa`。

## Risky Files

- `ai/skills/dev/database-query/src/config.ts`：配置查找逻辑，必须保持优先级不变。
- `ai/skills/dev/database-query/src/cli.ts`：CLI 参数兼容性。
- `ai/skills/dev/database-query/tests/check-sql.test.ts`：已有测试较集中，新增测试应避免污染全局环境变量。

## Validation Commands

```bash
pnpm --dir ai/skills/dev/database-query check
pnpm qa
```
