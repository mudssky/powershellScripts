# 设计本地与联网 Agent 模式

## Goal

降低轻量本地任务的固定上下文成本：让不需要时效信息或外部资料的配置修改、代码阅读和普通聊天不再默认携带搜索工具 schema，同时保留名称明确、可显式选择的联网搜索模式。

## Background

- 2026-08-17 的 Pi 测量显示，`pi-web-access` 及其工具 schema 约占 2.9k input tokens；对轻量模式占比明显。
- 当前 `full`、`project`、`no-skill` 本身保留较完整工具或 Skills，用户接受它们继续默认联网。
- 当前 `core|read|chat` 共用 `--no-skills --no-extensions -e pi-web-access`：
  - `core` 保留内置编码工具、项目 context 与搜索。
  - `read` 保留只读工具、项目 context 与搜索。
  - `chat` 移除项目 context 和内置工具，只保留搜索 extension tools。
- 当前 `offline` 使用中性 prompt，不保留 Skills、extensions、tools 或项目 context。
- `pi-mode` 行为由 `shell/shared.d/ai.sh::_pi_mode_run` 统一组装，并由 `scripts/bash/tests/agent-task.test.ts` 覆盖 Bash/Zsh 参数边界、帮助文案和搜索扩展 fail-closed。

## Requirements

- `full`、`project`、`no-skill` 的联网和资源行为保持不变。
- 轻量模式采用一致的 `-search` 后缀矩阵：
  - `core`：本地编码；原 `core` 搜索行为改名 `core-search`。
  - `read`：本地只读；原 `read` 搜索行为改名 `read-search`。
  - `chat`：本地聊天、无工具、无项目 context；行为来自原 `offline`。
  - `chat-search`：中性聊天 + 搜索、无项目 context 或内置工具；行为来自原 `chat`。
- 删除语义不明确的 `offline` 模式名，不保留兼容别名；仓库内现有调用方仅为自身帮助文案和测试。
- 本地模式不得加载 `pi-web-access`，也不得因搜索扩展缺失而失败。
- 显式搜索模式继续在 `pi-web-access` 缺失或不可读时 fail closed，返回现有资源错误语义。
- `PI_MODE_WEB_TOOLS` 继续只覆盖只读搜索模式的搜索工具名。
- 所有用户参数继续逐项原样转发；保持 Bash/Zsh 兼容性和宿主非零退出码透传。
- `agent-task` 的 Pi profile 仍只支持 `full|project|no-skill`，不把轻量父会话模式与 subagent profile 组合。
- Subagent 本地/搜索能力配置拆分到 agent-hub 任务 `08-17-subagent-local-search-capabilities`，本任务不修改 Pi/OMP Agent 配置。

## Acceptance Criteria

- [ ] `pi-mode` 帮助展示 `full|project|no-skill|core|core-search|read|read-search|chat|chat-search`，并明确本地、搜索和非网络沙箱边界。
- [ ] `core` argv 为无 Skills、无 extensions 的本地编码能力；`core-search` 在其基础上唯一加载 `pi-web-access`。
- [ ] `read` argv 只含本地 `read,grep,find,ls`；`read-search` 在其基础上增加可由 `PI_MODE_WEB_TOOLS` 覆盖的搜索工具。
- [ ] `chat` 使用中性本地聊天 prompt，且无 Skills、extensions、tools 和项目 context。
- [ ] `chat-search` 使用中性搜索聊天 prompt，只加载搜索 extension tools，不加载项目 context 或内置工具。
- [ ] 旧 `offline` 名称返回未知 mode；旧联网 `chat` 行为只通过 `chat-search` 可达。
- [ ] 搜索扩展缺失时，仅 `core-search|read-search|chat-search` fail closed；本地 `core|read|chat` 正常启动。
- [ ] Bash 与 Zsh 测试覆盖所有模式的稳定 argv、帮助、错误、环境覆盖和参数透传。
- [ ] 实际上下文探针使用既有固定 cwd、消息、thinking 与 provider token 口径，记录本地模式相对搜索对应模式的输入差值。
- [ ] `ai.sh` 顶部 Pi 上下文参考表更新为新模式名称和实测数据，不把字符长度与 token 混加。

## Out of Scope

- 不改变 Pi、OMP 上游实现。
- 不改变 `full`、`project`、`no-skill` 的默认联网行为。
- 不保留旧 `offline` 或旧联网 `chat` 的兼容别名。
- 不把任何无搜索工具模式宣称为进程级或模型级断网沙箱。
- 不修改 agent-config 中的 Pi/OMP worker 或搜索 agent；由独立任务处理。
