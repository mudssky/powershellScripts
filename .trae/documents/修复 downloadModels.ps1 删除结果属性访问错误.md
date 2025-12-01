## Plan
- [ ] 影响面分析 (Impact Analysis)
  - 修改文件: `ai/downloadModels.ps1`
  - 变更范围: 仅输出统计行的属性访问方式 (第 427–428 行)
  - 风险评估: 极低，仅影响控制台 UI 文本，不改动业务流程；与 `Invoke-ModelRemoval` 返回类型保持一致性
- [ ] 步骤1: 上下文确认 (Context Gathering)
  - 报错来源: `PropertyNotFoundException`，发生在 `ai/downloadModels.ps1:427` 与 `:428`
  - 代码现状: `Invoke-ModelRemoval` 返回的是哈希表：`@{ Removed = $ok; Failed = $fail }` (`ai/downloadModels.ps1:369`)
  - 现有访问: 下载结果使用 `[$key]` 访问 (`$result['Downloaded']`)，但删除结果错误使用点号属性 (`$removeResult.Removed`/`$removeResult.Failed`)
- [ ] 步骤2: 实施修复 (Implementation)
  - 将 `ai/downloadModels.ps1:427` 与 `:428` 的点号访问改为哈希表索引访问：
    - 427: `Write-Host "删除完成: $($removeResult['Removed']) 个模型" -ForegroundColor Red`
    - 428: `Write-Host "删除失败: $($removeResult['Failed']) 个模型" -ForegroundColor Yellow`
  - 保持与下载结果访问方式一致，避免类型不一致导致的后续问题
- [ ] 步骤3: 验证与回归检查 (Verification)
  - 重新执行模型下载脚本，观察尾部统计输出：
    - 应正确显示“删除完成: N 个模型 / 删除失败: M 个模型”而非空白
  - 建议在无模型可删时也能显示 `0`，确保健壮性
  - 可选: 为两个汇总变量增加显式强制为整数的格式化以避免字符串拼接异常

## 说明
- 错误本质: 哈希表不支持点号属性访问；应使用 `['key']` 索引方式。
- 该修复不影响业务逻辑，仅修正输出统计的数据读取方式。