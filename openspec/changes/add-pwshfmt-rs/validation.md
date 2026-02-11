## 验证记录

日期：2026-02-10

### 1) 单元测试

```bash
cargo test --manifest-path projects/clis/pwshfmt-rs/Cargo.toml
```

结果：7/7 通过，覆盖 check/write/fallback 与字符串/注释保护。

### 2) 命令级验证

- `--help`：展示参数与退出码说明。
- `--check`：检测到修复项时返回退出码 `2`。
- `--write`：完成命令名与参数名大小写修复并写回。
- `--strict-fallback`：在 `& $cmd` 不安全场景触发 fallback，输出 fallback 统计。
- `--git-changed --check`：无改动文件时快速退出。

### 3) 性能对比基线（样例文件）

测试样例：1 个存在 casing 问题的 `.ps1` 文件。

- `pwshfmt-rs --check`：约 `0.09s`
- `Format-PowerShellCode.ps1 -Strict`：约 `0.69s`

备注：该基线用于首版对比，后续可按仓库真实改动规模持续补充。
