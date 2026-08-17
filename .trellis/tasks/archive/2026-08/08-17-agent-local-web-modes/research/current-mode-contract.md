# 现有 Pi 模式契约与证据

## 实现位置

- `shell/shared.d/ai.sh::_pi_mode_help` 列出 `full|project|no-skill|core|read|chat|offline`。
- `shell/shared.d/ai.sh::_pi_mode_run` 是 `pi-mode` 与 Pi `agent-task` profile 的唯一参数组装入口。
- `scripts/bash/tests/agent-task.test.ts` 使用 fake host 在 Bash/Zsh 下验证 argv、错误码、帮助文案和参数边界。

## 当前轻量模式

`core|read|chat` 先共同执行：

```text
--no-skills --no-extensions -e <pi-web-access>
```

然后：

- `core` 不追加其它限制，保留默认编码工具和项目 context。
- `read` 使用 `--tools read,grep,find,ls,<web-tools>`。
- `chat` 使用 `--no-context-files --no-builtin-tools` 和中性搜索 prompt。
- `offline` 使用 `--no-skills --no-extensions --no-context-files --no-tools` 和中性本地 prompt。

因此 Web 扩展缺失检查当前错误地同时是 `core|read|chat` 的启动前置条件；拆出本地模式后，该检查必须只服务 `*-search`。

## 已确认调用方

仓库内模式名称引用只出现在 `ai.sh` 和 `agent-task.test.ts`。没有发现其它 Shell、PowerShell、文档或脚本调用 `pi-mode core|read|chat|offline`，所以采用 clean cutover，不需要兼容 alias。

## 测量口径

2026-08-17 的已有首轮探针固定：

- cwd：`/Users/mudssky/projects/powershellScripts`
- 消息：`仅回复 OK，不调用工具。`
- thinking：off
- provider input：`usage.input + usage.cacheRead + usage.cacheWrite`
- system prompt 与 tool schema 分别记录 JavaScript 字符长度

旧行为数据应迁移名称：

- 旧 `core` → `core-search`
- 旧 `read` → `read-search`
- 旧 `chat` → `chat-search`
- 旧 `offline` → `chat`

`core` 与 `read` 是新增行为，必须重新测量；不能只用字符数除四估算 provider tokens。
