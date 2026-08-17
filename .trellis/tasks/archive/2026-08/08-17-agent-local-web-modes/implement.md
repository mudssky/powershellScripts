# 实施计划：本地与搜索模式矩阵

## 实施顺序

1. 更新 `scripts/bash/tests/agent-task.test.ts` 的模式表，先表达新矩阵和旧 `offline` 拒绝行为。
2. 修改 `shell/shared.d/ai.sh::_pi_mode_help`：更新模式列表、行为说明、联网边界和示例。
3. 修改 `_pi_mode_run`：
   - 将 Web 扩展检查限制到 `core-search|read-search|chat-search`。
   - 为 `core|read|chat` 组装本地参数。
   - 复用现有 project/no-skill 路径，不改变 `agent-task` profile 支持范围。
4. 更新函数契约注释、prompt 变量名和错误说明，删除旧 `offline` 名称。
5. 运行定向测试并修复 Bash/Zsh 参数或数组兼容问题。
6. 使用真实 Pi 探针测量 `core/core-search`、`read/read-search`、`chat/chat-search` 的 DeepSeek Flash 与 Luna 首轮上下文。
7. 更新 `ai.sh` 顶部上下文参考表和解释；保留 token/chars 单位区分。
8. 运行最终质量检查和实际命令 smoke：帮助输出、本地模式在 Web 扩展缺失时启动、搜索模式缺失时 fail closed。

## 验证命令

```bash
pnpm vitest run scripts/bash/tests/agent-task.test.ts
bash -n shell/shared.d/ai.sh
zsh -n shell/shared.d/ai.sh
git diff --check
```

行为 smoke 使用隔离 fake host 测试覆盖 argv；上下文成本使用真实 `pi` 新会话探针，固定 cwd、消息、thinking 和模型。

## 风险点

- `chat` 语义发生 clean cutover：实现和帮助必须同时更新，避免用户以为它仍联网。
- `read` 的 `--tools` allowlist 在无 extension 时只能包含内置工具；测试必须证明没有残留 Web 工具名。
- Web 扩展检查若仍放在共享 `core|read|chat` 分支，会让本地模式错误 fail closed。
- 顶部历史测量表必须按行为迁移名称，不能把旧 `offline` 数值误留为已删除模式。
- Luna provider usage 含 Codex 订阅链路额外上下文，只用于实际使用参考；DeepSeek Flash 作为模式本体差值的主要依据。

## Review Gate

- PRD、design、implement 与最终实现的模式名称逐字一致。
- 没有修改 OMP、agent-task profile、Pi/OMP Agent 配置或父仓 submodule gitlink。
- 所有新增模式都有 Bash 与 Zsh argv 测试；旧 `offline` 明确测试为未知 mode。
