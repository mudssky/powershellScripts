## 目标
- 将计划输出从 `<plan>` 标签改为原生 Markdown 小节，提升可读性与一致性。
- 保留强制性的复选框格式与“影响面分析”要求。

## 拟修改内容
- 定位：`/c:/home/env/powershellScripts/ai/prompts/project rules/trae-project-rule-generator.md` 第 27–30 行所在的章节 “🧠 Chain of Thought & Planning (思考与规划)”。
- 将“必须在代码块中输出 `<plan>` 标签包裹的计划”改为“必须输出一个 Markdown 小节 `## Plan` + 复选框列表”。

## 修订文本（替换第 27–30 行的要点）
- 在编写任何代码之前，必须先输出一个“计划”小节，使用原生 Markdown 标题与复选框列表。
- 计划必须使用 Markdown 复选框格式 `- [ ]`，逐项列出目标与步骤。
- 计划内容中 **必须** 包含 “Impact Analysis（影响面分析）”：明确列出将被修改的文件路径与可能受影响的组件/模块/函数。
- 建议使用二级标题 `## Plan` 开启计划小节，并按固定结构编排（见下方模板）。

## 示例模板（推荐结构）
```md
## 🧭 Plan
- [ ] Goals：清晰描述要达成的结果
- [ ] Steps：
  - [ ] 步骤 1 …
  - [ ] 步骤 2 …
- [ ] Impact Analysis（必须）：
  - 修改文件：
    - `path/to/fileA`
    - `path/to/fileB`
  - 受影响组件/模块：
    - `ComponentOrFunctionA`
    - `ModuleB`
- [ ] Verification：说明验证策略（lint、type-check、test、OpenPreview 等）
```

## 影响面分析
- 修改文件：`/c:/home/env/powershellScripts/ai/prompts/project rules/trae-project-rule-generator.md`（仅限第 27–30 行所在段落的措辞与格式说明）。
- 受影响内容：所有引用或依赖 `<plan>` 标签的说明将改为使用 Markdown 标题与复选框，无需代码块包裹。
- 与其他章节的兼容性：不改变其余章节规则，仅提升计划展示的统一性与可读性。

## 验收标准
- 文档中“思考与规划”章节不再出现 `<plan>` 标签要求，而是明确要求 `## Plan` 小节与 `- [ ]` 复选框。
- 示例模板清晰、可直接复制使用，包含“Impact Analysis（必须）”与“Verification”。
- 不影响其他规则语义与执行流程。