## 验证计划（已完成）

日期：2026-02-11

说明：由于本变更改为“清空旧实现并重建”，以下为新的验证计划；历史探索版验证结果不再作为本次交付依据。

### 1) 单元与集成测试

- [x] 执行命令：`cargo test --manifest-path projects/clis/pwshfmt-rs/Cargo.toml`
- [x] 预期结果：单测与集成测试全部通过

### 2) 命令级行为验证

- [x] `--help`：展示新版命令与参数说明
- [x] check 模式：发现需修复项时返回非零退出码
- [x] write 模式：写回命令名/参数名 casing 修复
- [x] strict fallback：在不安全场景触发并记录回退
- [x] Git changed 与 path/glob：目标文件选择行为符合契约

### 3) 仓库级验证

- [x] 执行命令：`pnpm qa:pwsh`
- [x] 预期结果：格式化与测试流程通过
