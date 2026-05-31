# organize-classify 实施清单

## Checklist

- [x] 启动任务前读取 `trellis-before-dev` 和 `agent-skill-dev` 规范。
- [x] 创建 `ai/skills/dev/organize-classify/` 与 `references/`。
- [x] 编写 `SKILL.md`：
  - [x] frontmatter `name: organize-classify`。
  - [x] `description` 覆盖整理、分类、目录结构、文章结构、文件归属、项目结构等触发词。
  - [x] 主流程包含证据盘点、方法选择、方案输出、风险检查、执行确认、执行后验证。
  - [x] 写清 reference 读取导航。
- [x] 编写 `references/methodologies.md`：
  - [x] 通用方法论适用场景、输入信号、不适用情况和组合规则。
  - [x] 强调主分类维度收敛和辅助标签。
- [x] 编写 `references/programming-structure.md`：
  - [x] 跨语言通用结构原则。
  - [x] 框架官方文档优先规则。
  - [x] 编程目录整理前的证据检查清单。
- [x] 编写语言/生态 reference：
  - [x] `programming-python.md`
  - [x] `programming-javascript-typescript.md`
  - [x] `programming-go.md`
  - [x] `programming-rust.md`
  - [x] `programming-jvm.md`
  - [x] `programming-dotnet.md`
  - [x] `programming-scripts.md`
- [x] 编写 `references/examples.md`：
  - [x] 文件目录整理示例。
  - [x] 文章目录整理示例。
  - [x] 代码项目结构整理示例。
- [x] 校验所有 reference 均由 `SKILL.md` 直接可发现，不做深层跳转。
- [x] 运行 skill 结构校验：
  - [x] `python /Users/mudssky/.codex/skills/.system/skill-creator/scripts/quick_validate.py ai/skills/dev/organize-classify`
  - [x] 如缺少 Python 依赖，使用 `uv run --with pyyaml python ...`。
- [x] 如只新增文档型 skill，按项目规则不强制运行根目录 `pnpm qa`；若实施中新增脚本或代码，再执行对应 QA。

## Validation Commands

```bash
python /Users/mudssky/.codex/skills/.system/skill-creator/scripts/quick_validate.py ai/skills/dev/organize-classify
```

fallback：

```bash
uv run --with pyyaml python /Users/mudssky/.codex/skills/.system/skill-creator/scripts/quick_validate.py ai/skills/dev/organize-classify
```

## Risky Files and Rollback Points

- 新增路径：`ai/skills/dev/organize-classify/`。
- 不修改现有 skill，不修改安装脚本，不修改本机配置。
- 若内容失焦，删除新增 skill 目录即可回滚实现产物。

## Follow-up Checks Before Start

- [x] 用户已审阅 PRD、设计和实施清单，批准进入实现阶段。
- [x] 当前任务通过 `task.py start` 进入 `in_progress` 后再修改 `ai/skills/dev/organize-classify/`。
