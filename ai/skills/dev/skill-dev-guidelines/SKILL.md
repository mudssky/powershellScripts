---
name: skill-dev-guidelines
description: 指导在 powershellScripts 仓库的 `ai/skills/dev` 中创建、维护和检查本地 agent skill，覆盖纯文档、Python 脚本型、TypeScript 脚本型和本地 WebUI 边界。Use when 用户要求新增/维护本仓库 skill、选择 Python 或 TypeScript skill 结构、检查 SKILL.md/frontmatter/references/scripts 目录、规划验证命令或同步安装边界。
---

# Skill 开发规范

## 使用时机

用于本仓库 `ai/skills/dev/<skill-name>/` 下的本地 agent skill 开发、维护和检查。先把本 skill 当成导航层：它不替代仓库规范源，只帮助快速找到正确结构、语言路线和验证命令。

核心规范源：

- `ai/skills/SKILL_SPEC.md`
- `.trellis/spec/infra/agent-skill-dev.md`

如果本 skill 与规范源冲突，以规范源为准，并更新本 skill。

## 工作流程

1. 先读用户需求，判断是纯文档、Python 脚本型、TypeScript 脚本型，还是带本地 WebUI 的交互型 skill。
2. 读取本仓库规范源，确认当前规则没有变化。
3. 按类型读取对应 reference：
   - 通用结构、frontmatter、reference 分层、安装同步：`references/general.md`。
   - Python 轻量脚本、uv 项目、配置和测试：`references/python.md`。
   - TypeScript CLI、构建产物、根工具复用和测试：`references/typescript.md`。
4. 只创建必要文件。默认不要创建 `README.md`、`CHANGELOG.md`、`QUICK_REFERENCE.md` 等辅助文档。
5. 编写 `SKILL.md` 时保持主文件精简，把长规范和分支细节放进一层 `references/`。
6. 公共接口、CLI 入口和复杂逻辑必须说明核心功能、入参、返回值或退出码语义；中文注释解释设计意图，不复述基础语法。
7. 完成后运行 skill 基础校验，并按改动类型执行对应测试或仓库 QA。

## 路线选择

- 纯文档 skill：只有 `SKILL.md`，按需加 `references/` 或 `examples/`。
- Python 轻量脚本：只用标准库，入口为 `python scripts/<script>.py [args]`。
- Python 依赖型项目：有第三方依赖、复杂 WebUI 或包内模板时升级为 uv 项目，入口为 `uv run python -m <package>.cli [args]`。
- TypeScript 脚本型：源码在 `src/`，测试在 `tests/`，安装态入口必须是提交的 `scripts/*.js`。
- 本地 WebUI：默认绑定 `127.0.0.1`，打印 URL、PID、日志路径和自动关闭时间，用户数据写入 workspace，不写入 skill 安装目录。

## 验证入口

优先运行 skill frontmatter/结构校验：

```bash
uv run --with pyyaml python C:/Users/mudssky/.codex/skills/.system/skill-creator/scripts/quick_validate.py ai/skills/dev/<skill-name>
```

代码改动完成后按项目规则运行根目录 `pnpm qa`。如果只修改文档说明，可不执行 `pnpm qa`，但最终说明跳过原因。

## 边界

- 不把真实 secret、token、连接串、Cookie 或本机私有路径写入可提交示例。
- 不让安装态用户先安装依赖、构建源码或激活开发者本机虚拟环境。
- 不默认修改 `ai/skills/Install-Skills.ps1`、`skills.config.json` 或已有 skill；只有用户明确要求安装同步时才处理。
