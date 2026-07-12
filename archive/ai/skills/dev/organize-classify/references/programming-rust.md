# Rust 项目目录结构

## 先识别

- 是否有 `Cargo.toml`、workspace、crate 类型和 feature。
- 是 library、binary、多个 binary、CLI、服务还是工具集合。
- 是否使用框架或生成器；框架项目先查框架文档。

## 常见结构

单 crate：

```text
crate/
  Cargo.toml
  src/
    lib.rs
    main.rs
```

多个二进制入口：

```text
crate/
  src/
    lib.rs
    bin/
      tool_a.rs
      tool_b.rs
```

集成测试和示例：

```text
crate/
  tests/
    cli.rs
  examples/
    basic.rs
  benches/
    parse.rs
```

workspace：

```text
workspace/
  Cargo.toml
  crates/
    core/
    cli/
```

## 放置建议

- 可复用逻辑放 `src/lib.rs` 或库 crate，CLI 入口放 `src/main.rs` 或 `src/bin/*.rs`。
- integration tests 放 `tests/`，单元测试可与模块同文件或同目录。
- `target/` 是构建产物，不进入源码整理范围。
- workspace 中按 crate 边界组织，不把所有模块平铺到根 `src`。

## 避免

- 在 binary 入口中堆全部业务逻辑，导致无法测试。
- 轻易拆 workspace；小项目单 crate 更清晰。
- 移动文件后忘记更新 `mod` 声明、crate path、Cargo workspace members 和 include/exclude。
