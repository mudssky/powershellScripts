---
agent: codex
reasoning_effort: medium
---

检查当前 Git 变更，遵循 Conventional Commits 规范生成中文 commit message。
必要时根据仓库说明执行验证命令。
验证通过后执行 git commit。
不要执行 git push。
如果没有可提交变更、验证失败或提交失败，请以非零退出码结束并说明原因。
