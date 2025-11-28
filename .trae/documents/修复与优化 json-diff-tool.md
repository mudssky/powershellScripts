## 核心问题修复
- 修复 CLI 不输出结果：在 `src/index.ts` 将 `formatter.format(...)` 的返回值打印或写文件；修正传参类型为 `files: string[]`（当前在 src/index.ts:192-197 使用了 `@ts-expect-error` 并传入对象）。
- 对齐 README 与实际 CLI：移除未实现选项（如 `--recursive`、`--stats`、`--no-color`、`--output <file>`），或补齐实现；统一 `--output <format>` 文案为 `--output|-o` 并明确支持值。
- 补充 UNCHANGED 逻辑：在比较流程中产生 `DiffType.UNCHANGED`，使 `--show-unchanged` 生效，并与 Formatter 的统计一致。

## 性能优化
- 优化无序数组比较为 O(n)：使用 Map 记录元素频次（`JSON.stringify` 后作为键），避免 `includes` 的 O(n^2)；正确处理重复元素。
- 早停与跳过路径：新增 `--skip <regex>` 与 `--only <regex>` 两个过滤选项，减少大型 JSON 的遍历范围；当对象键和长度均等且哈希一致时可短路（可选实现）。
- 可配置 `maxDepth` 语义：明确“最大深度”是否包含数组索引层，必要时用统一的层级计算方法（对象层级+数组层级）替代仅按 `.` 统计。

## 代码质量与一致性
- 类型统一：理清 `DiffItem[]` 与整体结果结构；将 Formatter 的 JSON/YAML 输出使用 `ComparisonResult`（含 `files`, `differences`, `summary`），并在类型层统一导出。
- 移除重复统计实现：保留一个统计函数，比较器或格式化器二选一，避免分歧。
- 单元测试对齐类型：修正 `tests/formatter.test.ts` 中将 `DiffResult` 用作整体结果的错误用法，改为显式数组或引入 `ComparisonResult`。

## 用户体验改进
- CLI 选项增强：
  - `--output-file <path>` 将结果写入文件（复用 `OutputFormatter.outputToFile`），与 README 保持一致。
  - `--no-color` 控制着色（调用 `formatter.setColorEnabled(false)`）。
  - `--stats` 开关控制是否显示统计信息。
- 错误与帮助：当正则无效或文件不可读时，输出更明确的引导；补充示例到 `--help`。

## 测试与验证
- 新增 CLI 端到端测试：覆盖 `--output` 四种格式、`--ignore-order`、`--show-unchanged`、`--output-file`、`--no-color`、无效正则等。
- 大文件与性能基准测试：构造 10k~100k 键对象与复杂数组，验证时间与内存占用；记录基线以监控回归。
- 覆盖数组重复元素与深层嵌套、不同类型切换、`null/undefined` 混合等场景。

## 文档更新
- 统一 README 的“命令行选项/示例/输出格式”与实际实现；补充限制、性能提示与最佳实践。