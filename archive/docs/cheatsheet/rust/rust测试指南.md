# 🦀 Rust 测试 Cheatsheet

---

## 一、项目结构

```
my_project/
├── Cargo.toml
├── src/
│   ├── lib.rs          # 库代码 + 单元测试
│   └── main.rs         # 二进制入口
├── tests/              # 集成测试目录
│   ├── test_api.rs
│   └── common/         # 集成测试的共享辅助模块
│       └── mod.rs
├── benches/            # 基准测试目录
│   └── my_benchmark.rs
└── examples/           # 示例代码（也会被 cargo test 编译检查）
    └── demo.rs
```

---

## 二、单元测试（Unit Tests）

```rust
// src/lib.rs

/// 被测试的业务函数
fn add(a: i32, b: i32) -> i32 {
    a + b
}

fn divide(a: f64, b: f64) -> Result<f64, String> {
    if b == 0.0 {
        Err("除数不能为零".to_string())
    } else {
        Ok(a / b)
    }
}

// ========== 测试模块 ==========
#[cfg(test)]  // 只在 `cargo test` 时编译，不会进入生产构建
mod tests {
    use super::*;  // 导入父模块所有内容（包括私有函数）

    #[test]
    fn test_add() {
        assert_eq!(add(2, 3), 5);
    }

    #[test]
    fn test_add_negative() {
        assert_eq!(add(-1, -1), -2);
    }
}
```

---

## 三、断言宏（Assert Macros）

```rust
#[cfg(test)]
mod tests {
    #[test]
    fn demo_assertions() {
        // ✅ 基础断言
        assert!(true);
        assert!(1 + 1 == 2);

        // ✅ 相等/不等断言
        assert_eq!(4, 2 + 2);           // 左 == 右
        assert_ne!(4, 2 + 1);           // 左 != 右

        // ✅ 自定义错误消息（失败时更有用的提示）
        let result = 42;
        assert!(result > 0, "结果应该为正数，但实际是 {}", result);
        assert_eq!(result, 42, "期望42，实际得到 {}", result);

        // ✅ 浮点数比较（不要用 assert_eq! 直接比较浮点数）
        let x: f64 = 0.1 + 0.2;
        assert!((x - 0.3).abs() < f64::EPSILON * 4.0, "浮点误差过大");

        // ✅ 调试打印（Debug trait）
        // assert_eq! 和 assert_ne! 要求两边都实现了 Debug trait
        // 这样失败时才能打印出具体的值
        let v = vec![1, 2, 3];
        assert_eq!(v.len(), 3);
    }
}
```

---

## 四、测试属性（Test Attributes）

### 4.1 `#[should_panic]` — 期望测试Panic

```rust
#[test]
#[should_panic]
fn test_panic() {
    panic!("这是一个故意的panic");
}

// 更精确：指定 panic 消息必须包含某个子串
#[test]
#[should_panic(expected = "除数不能为零")]
fn test_divide_by_zero_message() {
    divide(1.0, 0.0).unwrap();
}
```

### 4.2 `#[ignore]` — 跳过测试

```rust
#[test]
#[ignore]  // 默认跳过，适合耗时长的测试
fn test_expensive_operation() {
    // 运行很慢的测试...
    std::thread::sleep(std::time::Duration::from_secs(60));
}

// 也可以加上原因说明
#[test]
#[ignore = "需要连接外部数据库"]
fn test_db_connection() {
    // ...
}
```

### 4.3 返回 `Result<T, E>` — 用 `?` 代替 `unwrap()`

```rust
#[test]
fn test_with_result() -> Result<(), String> {
    let result = divide(10.0, 2.0)?;  // 失败则测试自动失败
    assert_eq!(result, 5.0);
    Ok(())
}

// 也可以返回 Box<dyn Error>
#[test]
fn test_with_boxed_error() -> Result<(), Box<dyn std::error::Error>> {
    let data: i32 = "42".parse()?;
    assert_eq!(data, 42);
    Ok(())
}
```

---

## 五、集成测试（Integration Tests）

```rust
// tests/test_api.rs
// 注意：集成测试只能调用 pub 的公开接口

use my_project;  // 导入你的 crate

#[test]
fn test_public_api() {
    assert_eq!(my_project::public_add(2, 3), 5);
}
```

### 共享辅助代码

```rust
// tests/common/mod.rs  （注意：必须用 mod.rs 风格，否则会被当作独立测试文件）
pub fn setup() {
    // 初始化测试环境...
    println!("测试环境已初始化");
}

// tests/test_api.rs
mod common;  // 导入共享模块

#[test]
fn test_with_setup() {
    common::setup();
    // ... 执行实际测试
}
```

---

## 六、文档测试（Doc Tests）

```rust
/// 将两个数相加。
///
/// # Examples
///
/// ```
/// let result = my_project::public_add(2, 3);
/// assert_eq!(result, 5);
/// ```
pub fn public_add(a: i32, b: i32) -> i32 {
    a + b
}

/// 除法运算。
///
/// # Errors
///
/// 当除数为零时返回错误。
///
/// # Examples
///
/// ```
/// let result = my_project::divide(10.0, 2.0).unwrap();
/// assert_eq!(result, 5.0);
/// ```
///
/// ```should_panic
/// // 这个示例期望 panic
/// my_project::divide(1.0, 0.0).unwrap();
/// ```
///
/// ```no_run
/// // 这段代码能编译但不会被运行（适合网络/文件操作示例）
/// // std::fs::remove_dir_all("/tmp/test").unwrap();
/// ```
///
/// ```ignore
/// // 这段代码完全不会被编译或运行
/// // some_unstable_api();
/// ```
///
/// ```compile_fail
/// // 这段代码预期编译失败（用于展示编译器会拒绝的代码）
/// let x: i32 = "not a number";
/// ```
pub fn divide(a: f64, b: f64) -> Result<f64, String> {
    if b == 0.0 { Err("除数不能为零".to_string()) } else { Ok(a / b) }
}
```

### 文档测试中隐藏行

```rust
/// ```
/// # // 以 # 开头的行在文档中不显示，但会参与编译和运行
/// # fn main() -> Result<(), Box<dyn std::error::Error>> {
/// let result = my_project::public_add(1, 2);
/// assert_eq!(result, 3);
/// # Ok(())
/// # }
/// ```
```

---

## 七、异步测试（Async Tests）

### 使用 Tokio

```toml
# Cargo.toml
[dev-dependencies]
tokio = { version = "1", features = ["full", "test-util"] }
```

```rust
// 基本异步测试
#[tokio::test]
async fn test_async_operation() {
    let result = fetch_data().await;
    assert!(result.is_ok());
}

// 多线程运行时
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn test_multi_thread() {
    let result = concurrent_task().await;
    assert_eq!(result, 42);
}

// 控制时间（需要 test-util feature）
#[tokio::test(start_paused = true)]
async fn test_with_time() {
    // 时间一开始是暂停的，可以手动推进
    tokio::time::sleep(std::time::Duration::from_secs(3600)).await;
    // 实际上瞬间完成！
}
```

---

## 八、测试组织模式

### 8.1 测试 fixture / setup-teardown

```rust
struct TestContext {
    db: FakeDatabase,
    temp_dir: tempfile::TempDir,
}

impl TestContext {
    fn new() -> Self {
        Self {
            db: FakeDatabase::new(),
            temp_dir: tempfile::TempDir::new().unwrap(),
        }
    }
}

impl Drop for TestContext {
    fn drop(&mut self) {
        // 自动清理！Rust 的 Drop trait 天然是 teardown
        println!("清理测试资源...");
    }
}

#[test]
fn test_with_fixture() {
    let ctx = TestContext::new();  // setup
    ctx.db.insert("key", "value");
    assert_eq!(ctx.db.get("key"), Some("value"));
    // 函数结束时 Drop 自动调用 → teardown
}
```

### 8.2 测试辅助函数（避免重复代码）

```rust
#[cfg(test)]
mod tests {
    use super::*;

    // 辅助函数 — 不需要 #[test] 属性
    fn make_test_user(name: &str) -> User {
        User {
            name: name.to_string(),
            email: format!("{}@test.com", name),
            age: 25,
        }
    }

    #[test]
    fn test_user_display() {
        let user = make_test_user("alice");
        assert_eq!(user.to_string(), "alice <alice@test.com>");
    }

    #[test]
    fn test_user_validation() {
        let user = make_test_user("bob");
        assert!(user.is_valid());
    }
}
```

---

## 九、`cargo test` 命令行速查

```bash
# ========== 基础命令 ==========
cargo test                       # 运行所有测试（单元 + 集成 + 文档）
cargo test --lib                 # 只运行单元测试 (src/ 下的)
cargo test --doc                 # 只运行文档测试
cargo test --tests               # 只运行单元 + 集成测试（不含文档测试）
cargo test --test test_api       # 只运行 tests/test_api.rs

# ========== 过滤 ==========
cargo test test_add              # 运行名称包含 "test_add" 的测试
cargo test tests::               # 运行 tests 模块下的所有测试
cargo test -- --exact test_add   # 精确匹配测试名

# ========== 控制执行 ==========
cargo test -- --ignored          # 只运行被 #[ignore] 标记的测试
cargo test -- --include-ignored  # 运行所有测试，包括被 ignore 的
cargo test -- --test-threads=1   # 单线程串行执行（默认并行）
cargo test -- --nocapture        # 显示 println! 输出（默认被隐藏）
cargo test -- --show-output      # 只显示通过测试的输出

# ========== 其他 ==========
cargo test -p my_crate           # 只测试 workspace 中某个 crate
cargo test --release             # 用 release 模式编译并测试
cargo test --no-fail-fast        # 遇到失败不停止，继续运行所有测试
cargo test -- --list             # 列出所有测试，不运行
```

---

## 十、常用第三方测试库

### 10.1 `rstest` — 参数化测试

```toml
[dev-dependencies]
rstest = "0.18"
```

```rust
use rstest::rstest;

// 参数化测试：一个函数生成多个测试用例
#[rstest]
#[case(0, 0, 0)]
#[case(1, 1, 2)]
#[case(2, 3, 5)]
#[case(-1, 1, 0)]
fn test_add_parametrized(#[case] a: i32, #[case] b: i32, #[case] expected: i32) {
    assert_eq!(add(a, b), expected);
}

// fixture — 自动注入的 setup
#[fixture]
fn test_user() -> User {
    User::new("test", "test@example.com")
}

#[rstest]
fn test_user_is_valid(test_user: User) {
    assert!(test_user.is_valid());
}
```

### 10.2 `mockall` — Mock 对象

```toml
[dev-dependencies]
mockall = "0.12"
```

```rust
use mockall::automock;

#[automock]                     // 自动生成 MockUserRepository
trait UserRepository {
    fn find_by_id(&self, id: u64) -> Option<User>;
    fn save(&self, user: &User) -> Result<(), String>;
}

#[test]
fn test_with_mock() {
    let mut mock = MockUserRepository::new();

    // 设定期望行为
    mock.expect_find_by_id()
        .with(mockall::predicate::eq(1))   // 期望参数为 1
        .times(1)                           // 期望被调用 1 次
        .returning(|_| Some(User::new("alice")));  // 返回值

    // 使用 mock
    let user = mock.find_by_id(1);
    assert_eq!(user.unwrap().name, "alice");
    // Drop 时自动验证 times 约束
}
```

### 10.3 `insta` — 快照测试

```toml
[dev-dependencies]
insta = { version = "1", features = ["yaml"] }
```

```rust
use insta::assert_snapshot;
use insta::assert_yaml_snapshot;

#[test]
fn test_render_html() {
    let html = render_page("home");
    assert_snapshot!(html);
    // 第一次运行：生成快照文件 snapshots/test_name.snap
    // 以后运行：对比输出是否一致
}

#[test]
fn test_user_serialization() {
    let user = User::new("alice", 30);
    assert_yaml_snapshot!(user);
}

// CLI 管理快照：
// cargo insta test          # 运行测试并收集新快照
// cargo insta review        # 交互式审查快照差异
// cargo insta accept        # 接受所有新快照
```

### 10.4 `proptest` — 属性测试

```toml
[dev-dependencies]
proptest = "1"
```

```rust
use proptest::prelude::*;

proptest! {
    #[test]
    fn test_add_commutative(a in -1000..1000i32, b in -1000..1000i32) {
        // 加法交换律：自动生成数百种 a, b 的组合
        assert_eq!(add(a, b), add(b, a));
    }

    #[test]
    fn test_string_roundtrip(s in "\\PC{1,100}") {
        // 用正则表达式生成随机字符串
        let encoded = encode(&s);
        let decoded = decode(&encoded).unwrap();
        assert_eq!(s, decoded);
    }

    #[test]
    fn test_sort_preserves_length(mut v in prop::collection::vec(any::<i32>(), 0..100)) {
        let original_len = v.len();
        v.sort();
        assert_eq!(v.len(), original_len);
    }
}
```

### 10.5 `wiremock` — HTTP Mock Server

```toml
[dev-dependencies]
wiremock = "0.6"
```

```rust
use wiremock::{MockServer, Mock, ResponseTemplate};
use wiremock::matchers::{method, path};

#[tokio::test]
async fn test_http_client() {
    // 启动本地 mock server
    let mock_server = MockServer::start().await;

    // 注册 mock 行为
    Mock::given(method("GET"))
        .and(path("/api/users/1"))
        .respond_with(ResponseTemplate::new(200)
            .set_body_json(serde_json::json!({"name": "alice"})))
        .mount(&mock_server)
        .await;

    // 用 mock server 的 URL 调用你的客户端
    let client = ApiClient::new(&mock_server.uri());
    let user = client.get_user(1).await.unwrap();
    assert_eq!(user.name, "alice");
}
```

---

## 十一、代码覆盖率

```bash
# 方法一：使用 cargo-tarpaulin（最简单）
cargo install cargo-tarpaulin
cargo tarpaulin                        # 运行测试并生成覆盖率报告
cargo tarpaulin --out Html             # 生成 HTML 报告
cargo tarpaulin --ignore-tests         # 排除测试代码本身

# 方法二：使用 llvm-cov（更精确）
cargo install cargo-llvm-cov
cargo llvm-cov                         # 终端报告
cargo llvm-cov --html                  # HTML 报告
cargo llvm-cov --open                  # 生成并打开 HTML 报告
```

---

## 十二、高性能测试执行器 `cargo-nextest`

```bash
# 安装
cargo install cargo-nextest

# 使用（完全兼容 cargo test）
cargo nextest run                       # 运行所有测试（比 cargo test 快 2-3x）
cargo nextest run test_add              # 过滤
cargo nextest run --retries 2           # 失败重试 2 次
cargo nextest run -E 'test(add)'        # 过滤表达式
cargo nextest list                      # 列出所有测试

# 注意：nextest 不支持文档测试，文档测试仍需 cargo test --doc
```

---

## 十三、常用配置

### `Cargo.toml` 测试相关配置

```toml
# 开发依赖（只在测试/示例/bench 中编译）
[dev-dependencies]
tempfile = "3"
pretty_assertions = "1"   # 更漂亮的 assert_eq! 差异输出
test-case = "3"            # 另一个参数化测试库

# 定义独立的集成测试二进制
[[test]]
name = "integration"
path = "tests/integration/main.rs"
harness = true             # true = 使用标准测试框架; false = 自定义 main

# Profile 设置：让测试构建更快
[profile.test]
opt-level = 0
debug = true

# 让测试中的依赖也使用 release 优化（适合 CPU 密集型测试）
[profile.test.package."*"]
opt-level = 2
```

---

> **💡 小提示**
>
> - `assert_eq!` 和 `assert_ne!` 要求类型实现 `Debug` + `PartialEq`
> - 测试函数默认**并行**运行，共享状态需要 `Mutex` 或使用 `--test-threads=1`
> - `#[cfg(test)]` 模块中的代码**可以访问私有函数**，这是 Rust 的设计特性
> - 使用 `pretty_assertions` crate 可以让失败时的 diff 输出更易读（彩色高亮）
> - 每个 `tests/` 下的 `.rs` 文件会被编译为**独立的 crate**
