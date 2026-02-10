Rust 跨平台单文件脚本的核心目标通常有三个：

- 单文件源码，便于复制与维护
- 跨平台执行（Windows / Linux / macOS）
- 兼顾开发效率与最终分发体验

Rust 本质是编译型语言，不是传统脚本语言，所以“单文件直接运行”最佳实践一般分为两条线：

- **开发态**：像脚本一样快速运行（`cargo-script` / `rust-script`）
- **分发态**：编译成单一可执行文件（`cargo build --release`）

---

## 方案一：`rust-script`（推荐开发态）

`rust-script` 可以直接运行单个 `.rs` 文件，并支持在文件头内声明依赖，体验最接近 Python `uv` 或 Deno。

### 1) 安装

```bash
cargo install rust-script
```

### 2) 编写单文件脚本（含依赖）

```rust
#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! anyhow = "1"
//! clap = { version = "4", features = ["derive"] }
//! reqwest = { version = "0.12", features = ["blocking", "json", "rustls-tls"] }
//! serde = { version = "1", features = ["derive"] }
//! ```

use anyhow::Result;
use clap::Parser;

#[derive(Parser, Debug)]
struct Args {
    #[arg(long, default_value = "https://httpbin.org/get")]
    url: String,
}

fn main() -> Result<()> {
    let args = Args::parse();
    let body = reqwest::blocking::get(&args.url)?.text()?;
    println!("fetched {} bytes", body.len());
    Ok(())
}
```

### 3) 执行

Linux / macOS:

```bash
chmod +x script.rs
./script.rs --url https://httpbin.org/get
```

Windows（建议直接调用）：

```powershell
rust-script .\script.rs --url https://httpbin.org/get
```

可选 `.cmd` 包装器：

```bat
@rust-script "%~dp0script.rs" %*
```

**优点**：开发快、单文件清晰、依赖声明集中。  
**缺点**：目标机器需要 Rust 工具链或 `rust-script`。

---

## 方案二：标准 Cargo 项目（推荐分发态）

如果要给其他人“拿来即用”，最稳妥的是编译成单一可执行文件。

### 1) 初始化

```bash
cargo new mytool
cd mytool
```

### 2) 编译

```bash
cargo build --release
```

输出位于：

- Windows: `target/release/mytool.exe`
- Linux/macOS: `target/release/mytool`

### 3) 跨平台构建（可选）

```bash
rustup target add x86_64-pc-windows-msvc
rustup target add x86_64-unknown-linux-gnu
rustup target add aarch64-apple-darwin
```

可配合 CI 分平台构建并发布二进制。

**优点**：启动快、运行快、分发友好。  
**缺点**：不再是“仅单文件源码”体验，需要构建步骤。

---

## 方案三：shebang + `cargo`（轻量但受限）

可以用 shebang 调用 `cargo run`，但通常需要项目目录（`Cargo.toml`），对“真正单文件”帮助有限，因此不作为首选。

---

## 依赖管理最佳实践

- 开发态单文件：优先 `rust-script` 头部依赖块。
- 稳定工具开发：迁移到标准 `Cargo.toml`，便于版本锁定与测试。
- 网络请求优先 `rustls`（跨平台更稳，减少系统 OpenSSL 差异）。

---

## 跨平台脚本设计建议

- 路径处理使用 `std::path::Path` / `PathBuf`。
- 命令行参数统一用 `clap`。
- 错误处理统一返回 `anyhow::Result<()>`。
- 文件遍历用 `walkdir`，忽略规则可用 `ignore`。
- 不要硬编码 shell 命令；确需调用时分平台封装。

---

## 场景建议

1. **个人自动化脚本（追求迭代速度）**：`rust-script`
2. **团队共享工具（追求稳定分发）**：Cargo + release 二进制
3. **高性能批处理/扫描器**：直接 Rust 二进制，不走脚本运行器

---

## 总结

- 想要“Rust 也像脚本一样快写快跑”：选 `rust-script`。
- 想要“跨平台一键可用、性能稳定”：编译成 release 二进制。
- 实战里通常是：**开发态用 `rust-script`，发布态用二进制**。
