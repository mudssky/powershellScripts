# Repo Ops Skill 维护

## 何时更新

在以下情况更新 `.agents/skills/repo-ops/`：

- 新增仓库运维域，例如新的自托管服务、网关、备份恢复流程或部署脚本。
- LiteLLM、LobeHub、安装流程的关键命令、文件路径、环境变量契约发生变化。
- 用户希望把一次排查经验沉淀成后续 agent 可复用的操作知识。
- `SKILL.md` 的触发范围和实际 reference 内容不一致。

## 修改流程

1. 先读 `SKILL.md` 和相关 `references/*.md`。
2. 搜索仓库真实入口文件，确认命令、路径和变量来自当前代码或文档。
3. 小改动直接更新对应 reference；新增运维域时创建新的 `references/<domain>.md`，并在 `SKILL.md` 的 Reference 选择里加路由。
4. 如果触发范围变化，更新 `SKILL.md` frontmatter `description`，保持具体、可触发、不过度泛化。
5. 如果 UI 展示语需要同步，更新或重新生成 `agents/openai.yaml`。
6. 运行 skill 校验和项目 QA，并记录无法验证的环境原因。

## 内容原则

- `SKILL.md` 只放触发场景、通用工作流、安全边界和 reference 导航。
- 具体命令、路径、排查经验放入 `references/`。
- 不创建额外 `README.md`、`CHANGELOG.md`、`QUICK_REFERENCE.md` 等辅助文档。
- 不复制大段上游文档；只记录本仓库可执行约定和入口。
- 不写真实 secret，不写完整 `.env` 内容，不在示例中使用真实 token、密码或连接串。

## 校验命令

优先使用 skill-creator 的校验脚本：

```bash
python /Users/mudssky/.codex/skills/.system/skill-creator/scripts/quick_validate.py .agents/skills/repo-ops
```

如果本机 Python 缺少 `yaml` 模块，可用带依赖的临时运行方式：

```bash
uv run --with pyyaml python /Users/mudssky/.codex/skills/.system/skill-creator/scripts/quick_validate.py .agents/skills/repo-ops
```

项目质量检查：

```bash
pnpm qa
```

## openai.yaml

`agents/openai.yaml` 是 UI 元数据，不是 agent 的主要执行说明。更新时保持：

- `display_name` 简短。
- `short_description` 能概括 LiteLLM、LobeHub 和依赖安装。
- `default_prompt` 必须显式包含 `$repo-ops`。

如需重新生成，可使用 skill-creator 初始化脚本或 `generate_openai_yaml.py`，并先阅读系统 skill-creator 的 `references/openai_yaml.md`。
