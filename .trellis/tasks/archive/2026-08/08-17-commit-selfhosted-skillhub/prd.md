# 提交 selfhosted SkillHub 快捷入口

## Goal

将现有未跟踪文件 `shell/shared.d/selfhosted.sh` 作为独立功能提交，提供依赖自建 Forgejo npm registry 的 `skillhub()` Shell 快捷入口。

## Confirmed Facts

- 文件仅包含一个 `skillhub()` 函数，兼容 Bash/Zsh。
- 公共依赖使用 `https://registry.npmjs.org/`，`@agent-skills` scope 使用 `http://macmini:30001/api/packages/mudssky/npm/`。
- 参数原样传递给 `@agent-skills/cli`；缺少 `npx` 时打印提示并返回 0。
- 当前工作树除本任务文件和 Trellis 任务目录外没有其他未提交代码改动。

## Requirements

- 只提交 `shell/shared.d/selfhosted.sh`，不得混入已完成任务、任务记录或其他文件。
- 不修改文件现有行为和 registry 地址。
- 提交前运行 Bash/Zsh 语法检查与 `git diff --check`。
- 使用 Conventional Commits 中文提交信息。
- 不推送远程；推送需另行明确授权。

## Acceptance Criteria

- [ ] `bash -n shell/shared.d/selfhosted.sh` 通过。
- [ ] `zsh -n shell/shared.d/selfhosted.sh` 通过。
- [ ] `git diff --check -- shell/shared.d/selfhosted.sh` 通过。
- [ ] 新提交只包含 `shell/shared.d/selfhosted.sh`。
- [ ] 提交后工作树不再显示该文件为未跟踪。

## Out of Scope

- 不执行真实 `npx` 或访问内网 registry。
- 不修改 Shell 加载机制、SkillHub 配置或其他共享脚本。
- 不推送远程分支。

## Risks

- `http://macmini:30001` 依赖本机网络和服务可用性；本任务只提交既有配置，不验证远程服务。
