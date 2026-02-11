## 1. CLI 与项目骨架

- [x] 1.1 初始化 `projects/clis/pwshfmt-rs` Rust 项目结构与基础依赖
- [x] 1.2 实现 CLI 参数解析（`--git-changed`、`--path`、`--recurse`、`--check`、`--write`、`--strict-fallback`）
- [x] 1.3 增加帮助文本与退出码约定（成功/需修复/执行失败）

## 2. 文件收集与执行模型

- [x] 2.1 实现 Git 改动文件收集，仅保留 `.ps1` / `.psm1` / `.psd1`
- [x] 2.2 实现路径模式收集（`--path` + `--recurse`）并去重
- [x] 2.3 接入并发处理与处理结果汇总（成功/跳过/失败）

## 3. Casing correction 子集

- [x] 3.1 实现命令名与参数名 casing 修复策略
- [x] 3.2 确保字符串字面量与注释不被修改
- [x] 3.3 实现 no-op 写回优化（内容一致不写盘）

## 4. 兼容回退与接入

- [x] 4.1 实现 `--strict-fallback`：不安全场景回退现有 `pwsh` 严格链路
- [x] 4.2 增加接入脚本/命令（例如新增 `format:pwsh:rs`）
- [x] 4.3 编写故障输出与回退统计，便于排查

## 5. 文档与验证

- [x] 5.1 更新 Rust 与格式化相关文档，补充使用示例与边界
- [x] 5.2 增加最小测试/样例覆盖（check/write/fallback）
- [x] 5.3 完成端到端验证并记录性能对比基线
