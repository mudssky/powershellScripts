# pwshfmt-rs

`pwshfmt-rs` 是一个面向 PowerShell 脚本的 Rust CLI，当前提供“命令/参数大小写修正 + strict fallback”能力。

## 设计目标

- 模块化架构：`cli` / `config` / `discovery` / `processor` / `formatter` / `summary` / `error`
- 可扩展 CLI：基于 `clap derive` 子命令模型
- 分层配置：`CLI > ENV > config file > built-in defaults`
- 文件发现：`walkdir + globset`
- 统一诊断：`miette`

## 命令行

```bash
# 查看帮助
cargo run --manifest-path ./Cargo.toml -- --help

# check 模式：仅校验，不写回
cargo run --manifest-path ./Cargo.toml -- check --git-changed

# write 模式：写回修复
cargo run --manifest-path ./Cargo.toml -- write --path . --recurse

# 开启 strict fallback
cargo run --manifest-path ./Cargo.toml -- write --git-changed --strict-fallback
```

### 子命令

- `check`：仅检查并返回待修复结果
- `write`：执行写回

### 全局参数

- `--config <FILE>`：指定配置文件（默认自动读取 `./pwshfmt-rs.toml`）
- `--git-changed[=<BOOL>]`：处理 Git 改动文件
- `--path <PATH_OR_GLOB>`：路径或 glob，可重复传入
- `--recurse[=<BOOL>]`：目录递归扫描
- `--strict-fallback[=<BOOL>]`：不安全语法时回退严格链路
- `--fallback-script <FILE>`：严格回退脚本路径

## 配置文件

默认配置文件名：`pwshfmt-rs.toml`

```toml
git_changed = false
paths = []
recurse = false
strict_fallback = false
fallback_script = "scripts/pwsh/devops/Format-PowerShellCode.ps1"
```

## 环境变量

- 前缀：`PWSHFMT_RS_`
- 示例：
  - `PWSHFMT_RS_RECURSE=true`
  - `PWSHFMT_RS_GIT_CHANGED=true`

## 退出码

- `0`：成功
- `2`：`check` 模式下发现需修复项
- `1`：执行失败

## 说明

- 当前仅修复命令名与参数名大小写。
- 字符串字面量、注释、here-string 内容不会被修改。
- 若检测到不安全语法（例如动态调用），可通过 `strict_fallback` 调用既有严格脚本链路。
- 错误输出基于 `miette`，格式较旧日志版本更结构化（属于预期变更）。
