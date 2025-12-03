## 原因与定位
- 报错来源：Terminal#398-463 显示 Pester 5 不再支持无短横线的 Legacy Should 语法。
- 失败用例位置：
  - c:\home\env\powershellScripts\psutils\tests\profile_windows.Tests.ps1:18,19,31,32 使用了 `Should BeGreaterThan/BeLessThan`。
  - c:\home\env\powershellScripts\psutils\tests\profile_unix.Tests.ps1:18,19,31,32 同样使用了旧语法（当前环境下被跳过，但应一并修复）。
- 现有配置：c:\home\env\powershellScripts\PesterConfiguration.ps1 已使用 Pester v5 的 `New-PesterConfiguration`。

## Plan
- [ ] Impact Analysis (影响面分析):
  - 修改文件：`psutils/tests/profile_windows.Tests.ps1`, `psutils/tests/profile_unix.Tests.ps1`
  - 潜在风险：极低，仅断言语法修复，不改变测试逻辑与阈值
- [ ] Step 1: Context Gathering（上下文获取）
  - 复核 Pester v5 配置与项目中其它测试文件的断言用法（已通过检索确认仅上述两文件使用旧语法）
- [ ] Step 2: Implementation（实现）
  - 将以下断言统一迁移到 Pester 5 语法：
    - `Should BeGreaterThan 0` → `Should -BeGreaterThan 0`
    - `Should BeLessThan 10000` → `Should -BeLessThan 10000`
  - 同步修复 Unix 对应文件的相同行
- [ ] Step 3: Verification（验证）
  - 运行 `pnpm test`，确认：
    - Windows Profile 两个用例通过
    - Unix Profile 在非 Unix 环境仍正确被跳过
    - 总测试数与覆盖率稳定，无新增失败

## 变更预览（示例）
- `c:\home\env\powershellScripts\psutils\tests\profile_windows.Tests.ps1`
  - 18: `$ms | Should -BeGreaterThan 0`
  - 19: `$ms | Should -BeLessThan 10000`
  - 31: `$ms | Should -BeGreaterThan 0`
  - 32: `$ms | Should -BeLessThan 10000`
- `c:\home\env\powershellScripts\psutils\tests\profile_unix.Tests.ps1` 同步替换上述 4 行。

## 备注
- 参考：Pester v5 迁移指南 https://pester.dev/docs/v5/migrations/v3-to-v4
- 本次仅为语法迁移，不调整性能阈值与测试结构。