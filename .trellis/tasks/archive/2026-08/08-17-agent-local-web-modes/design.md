# 技术设计：本地与搜索模式矩阵

## 设计边界

只修改 `shell/shared.d/ai.sh` 的 Pi 父会话模式组装、帮助和上下文参考注释，以及 `scripts/bash/tests/agent-task.test.ts` 的对应契约测试。`agent-task` profile、OMP mode 和其它宿主不变。

## 模式契约

| 模式 | Skills | Extensions | 项目 context | 内置工具 | 搜索工具 |
| --- | --- | --- | --- | --- | --- |
| `full` | 默认 | 默认 | 默认 | 默认 | 默认 |
| `project` | 仅显式项目 Skills | 默认 | 默认 | 默认 | 默认 |
| `no-skill` | 无 | 默认 | 默认 | 默认 | 默认 |
| `core` | 无 | 无 | 保留 | 默认编码工具 | 无 |
| `core-search` | 无 | 仅 `pi-web-access` | 保留 | 默认编码工具 | 有 |
| `read` | 无 | 无 | 保留 | `read,grep,find,ls` | 无 |
| `read-search` | 无 | 仅 `pi-web-access` | 保留 | `read,grep,find,ls` | `PI_MODE_WEB_TOOLS` |
| `chat` | 无 | 无 | 无 | 无 | 无 |
| `chat-search` | 无 | 仅 `pi-web-access` | 无 | 无 | 有 |

`chat` 沿用原 `offline` 的中性本地 prompt；`chat-search` 沿用原 `chat` 的中性搜索 prompt。旧 `offline` 不做兼容映射。

## 参数组装

`_pi_mode_run` 继续作为唯一组装入口：

- `core`：`--no-skills --no-extensions`
- `core-search`：`--no-skills --no-extensions -e "$web_extension"`
- `read`：`--no-skills --no-extensions --tools read,grep,find,ls`
- `read-search`：`--no-skills --no-extensions -e "$web_extension" --tools "read,grep,find,ls,$web_tools"`
- `chat`：`--no-skills --no-extensions --no-context-files --no-tools --system-prompt "$local_chat_prompt"`
- `chat-search`：`--no-skills --no-extensions -e "$web_extension" --no-context-files --no-builtin-tools --system-prompt "$search_chat_prompt"`

Web 扩展文件检查只在 `*-search` 分支执行。本地模式不读取 `PI_MODE_WEB_EXTENSION`，因此扩展缺失不应影响启动。

## 命名与兼容

这是有意的 clean cutover：

- 旧 `core` → `core-search`，新 `core` 为本地模式。
- 旧 `read` → `read-search`，新 `read` 为本地模式。
- 旧 `chat` → `chat-search`，新 `chat` 采用旧 `offline` 行为。
- 旧 `offline` 删除。

仓库搜索未发现外部脚本调用方；只迁移帮助、注释和测试。不加入 alias、deprecated 分支或警告期。

## 上下文测量

实现完成后复用 2026-08-17 已建立的探针口径：

- cwd：`/Users/mudssky/projects/powershellScripts`
- 消息：`仅回复 OK，不调用工具。`
- thinking：off
- 模型：`local/deepseek-v4-flash`、`local/gpt-5.6-luna`
- provider input：`usage.input + usage.cacheRead + usage.cacheWrite`
- system prompt：JavaScript 字符长度
- tool schema：`JSON.stringify(payload.tools).length`

旧数据按行为迁移到 `core-search/read-search/chat-search/chat`；新测 `core/read`。如果插件或 Skill 快照同时变化，注释必须明确这是新的安装快照，不能把差值全部归因于模式改动。

## 回滚

变更集中在一个 Shell case 分支和一组测试。回滚时恢复旧模式名、旧参数表和测量注释即可；没有持久状态迁移或配置文件格式变化。
