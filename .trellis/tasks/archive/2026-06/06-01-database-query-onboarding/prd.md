# database-query 开箱即用体验

## Goal

降低 `database-query` skill 安装后的首次使用门槛，让 agent 能根据环境自行补齐数据库客户端、生成最小配置，并在常见关系型数据库配置中减少冗余字段。

用户价值：

- 配置中已有 `defaultDatabase` 时，不必重复维护 `databases[]`。
- 新机器安装 skill 后，agent 可以先运行 `doctor` 判断缺少哪些底层工具，再自行选择安装方式。
- 没有配置文件时，可以用 CLI 生成最小全局配置模板，再由用户或 agent 填入连接信息。

## Confirmed Facts

- 当前 `resolveOptionalDatabase()` 在 `databases[]` 为空且实例存在 `defaultDatabase` 时会报错。
- `planner` 已经使用 `target.database?.name ?? target.instance.defaultDatabase` 解析关系型执行数据库名。
- 当前 `doctor` 只输出缺失工具和安装提示，不提供自动安装；用户明确不希望新增 `doctor --install`。
- 当前全局配置查找路径已支持 `$XDG_CONFIG_HOME/database-query/` 与 `~/.config/database-query/`。

## Requirements

- 若实例配置了 `defaultDatabase`，应允许省略 `databases[]`，关系型 `exec` / `client` 仍能使用该默认库。
- 如果用户显式传入 `--database`，但实例没有 `databases[]` 候选，则应允许直接使用显式数据库名，不强制预登记。
- 如果实例既没有 `databases[]`，也没有 `defaultDatabase`，且命令需要数据库，仍应报错要求提供 `--database` 或配置默认库。
- `context` 输出应继续显示 `defaultDatabase`；省略 `databases[]` 时不需要伪造候选列表。
- 不新增 `doctor --install` 或自动安装底层客户端能力。
- `doctor` 与文档应强调由 agent 根据当前平台、权限和包管理器自行决定安装命令；安装提示仅作为参考。
- 增加配置初始化能力，能生成最小全局配置模板，不覆盖已有配置，且不写入真实密码。
- 初始化出的配置应避免重复写入已有内置默认值，只保留 schema、实例示例和必要默认目标。

## Acceptance Criteria

- [ ] `defaultDatabase` 存在且 `databases[]` 省略时，`client --print-command` 能生成带目标库的 PostgreSQL/MySQL 启动计划。
- [ ] 显式 `--database` 存在且 `databases[]` 省略时，能使用显式数据库名。
- [ ] 需要数据库但无法从 `--database` 或 `defaultDatabase` 得到数据库名时，返回清晰错误。
- [ ] `init-config --global --print` 输出最小配置模板，不包含真实密钥。
- [ ] `init-config --global` 能写入 XDG 全局配置目录；目标已存在时默认拒绝覆盖。
- [ ] `doctor` 输出和文档说明不自动安装，agent 应基于提示自行选择安装方式。
- [ ] 构建产物 `scripts/database-query.js` 与 TypeScript 源码同步。
- [ ] 自动化测试覆盖默认库省略 `databases[]`、显式数据库、初始化配置和 doctor 文案。

## Out of Scope

- 不实现 `doctor --install` 或自动执行包管理器安装。
- 不从 Codex/Claude/MCP 配置自动导入真实连接。
- 不联网检测包管理器可用性或数据库连通性。
- 不把真实密码写入生成的模板。

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
