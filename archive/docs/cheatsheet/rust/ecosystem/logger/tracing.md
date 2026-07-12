# 🦀 Tracing × Axum Cheatsheet

## 📦 1. Cargo.toml 依赖

```toml
[dependencies]
# Web 框架
axum = "0.8"
tokio = { version = "1", features = ["full"] }

# Tracing 核心
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter", "json"] }

# HTTP 请求追踪中间件
tower-http = { version = "0.6", features = ["trace", "request-id", "propagate-header", "cors"] }
tower = "0.5"

# 日志文件轮转（可选）
tracing-appender = "0.2"
```

---

## 🚀 2. 最小启动模板

```rust
use axum::{routing::get, Router};
use tower_http::trace::TraceLayer;
use tracing::info;

#[tokio::main]
async fn main() {
    // 初始化 tracing（默认从 RUST_LOG 读取级别）
    tracing_subscriber::fmt::init();

    let app = Router::new()
        .route("/", get(|| async { "Hello, World!" }))
        .layer(TraceLayer::new_for_http()); // 一行搞定 HTTP 追踪

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();
    info!("🚀 Server listening on 0.0.0.0:3000");
    axum::serve(listener, app).await.unwrap();
}
```

运行：`RUST_LOG=info cargo run`

---

## 🔧 3. Subscriber 配置详解

### 3.1 基础配置 — EnvFilter + 格式化

```rust
use tracing_subscriber::{fmt, EnvFilter, prelude::*};

fn init_tracing() {
    let env_filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| {
            // 默认级别: axum 相关设为 debug，其他为 info
            EnvFilter::new("info,my_app=debug,tower_http=debug,axum=trace")
        });

    tracing_subscriber::registry()
        .with(env_filter)
        .with(
            fmt::layer()
                .with_target(true)       // 显示日志来源模块
                .with_thread_ids(false)   // 不显示线程 ID
                .with_level(true)         // 显示日志级别
                .with_file(true)          // 显示文件名
                .with_line_number(true)   // 显示行号
                .compact()               // 紧凑格式（可选 .pretty()）
        )
        .init();
}
```

### 3.2 JSON 格式输出（适合 ELK / Loki / Datadog 等日志收集系统）

```rust
use tracing_subscriber::{fmt, EnvFilter, prelude::*};

fn init_tracing_json() {
    tracing_subscriber::registry()
        .with(EnvFilter::new("info,tower_http=debug"))
        .with(
            fmt::layer()
                .json()                    // JSON 格式
                .with_span_list(true)      // 包含 span 嵌套列表
                .with_current_span(true)   // 包含当前 span
                .with_thread_names(true)
                .flatten_event(true)       // 将 event 字段展平到顶层
        )
        .init();
}
```

### 3.3 多输出 — 终端 + 文件 同时输出

```rust
use std::{fs::File, sync::Arc};
use tracing_subscriber::{fmt, filter::LevelFilter, prelude::*};

fn init_tracing_multi_output() {
    // Layer 1: 终端输出 (INFO 及以上)
    let stdout_layer = fmt::layer()
        .pretty()
        .with_filter(LevelFilter::INFO);

    // Layer 2: 文件输出 (DEBUG 及以上，JSON 格式)
    let log_file = File::create("app.log").expect("Failed to create log file");
    let file_layer = fmt::layer()
        .json()
        .with_writer(Arc::new(log_file))
        .with_filter(LevelFilter::DEBUG);

    tracing_subscriber::registry()
        .with(stdout_layer)
        .with(file_layer)
        .init();
}
```

### 3.4 日志文件按天轮转（tracing-appender）

```rust
use tracing_subscriber::{fmt, EnvFilter, prelude::*};

fn init_tracing_with_rolling_file() {
    // 按天生成日志文件: logs/app.2026-04-05.log
    let file_appender = tracing_appender::rolling::daily("logs", "app.log");
    // non_blocking 避免 I/O 阻塞异步运行时
    let (non_blocking, _guard) = tracing_appender::non_blocking(file_appender);

    // ⚠️ _guard 必须保留在 main 作用域中，drop 后日志停止写入！

    let file_layer = fmt::layer()
        .json()
        .with_writer(non_blocking);

    let stdout_layer = fmt::layer()
        .compact()
        .with_filter(EnvFilter::new("info"));

    tracing_subscriber::registry()
        .with(stdout_layer)
        .with(file_layer)
        .init();

    // 返回 _guard 或将其存储在 main 中
}

#[tokio::main]
async fn main() {
    // ⚠️ 关键: _guard 必须绑定到变量，否则立即 drop
    let _guard = init_tracing_with_rolling_file_v2();
    // ... 启动服务 ...
}

// 改进版：返回 guard
fn init_tracing_with_rolling_file_v2() -> tracing_appender::non_blocking::WorkerGuard {
    let file_appender = tracing_appender::rolling::daily("logs", "app.log");
    let (non_blocking, guard) = tracing_appender::non_blocking(file_appender);

    tracing_subscriber::registry()
        .with(EnvFilter::new("info"))
        .with(fmt::layer().compact())
        .with(fmt::layer().json().with_writer(non_blocking))
        .init();

    guard // 返回 guard，由调用方持有
}
```

---

## 🌐 4. TraceLayer（tower-http）高级配置

### 4.1 默认 TraceLayer

```rust
use tower_http::trace::TraceLayer;

let app = Router::new()
    .route("/", get(handler))
    .layer(TraceLayer::new_for_http());
```

### 4.2 自定义 TraceLayer — 控制请求/响应日志内容

```rust
use axum::{routing::get, Router};
use tower_http::trace::{self, TraceLayer};
use tracing::Level;

let app = Router::new()
    .route("/", get(handler))
    .layer(
        TraceLayer::new_for_http()
            .make_span_with(trace::DefaultMakeSpan::new().level(Level::INFO))
            .on_request(trace::DefaultOnRequest::new().level(Level::INFO))
            .on_response(
                trace::DefaultOnResponse::new()
                    .level(Level::INFO)
                    .latency_unit(tower_http::LatencyUnit::Micros)  // 延迟单位
            )
            .on_failure(trace::DefaultOnFailure::new().level(Level::ERROR))
    );
```

### 4.3 完全自定义 Span（增加 request_id、method、path）

```rust
use axum::{extract::Request, routing::get, Router};
use tower_http::trace::TraceLayer;
use tracing::{Level, Span};
use std::time::Duration;

let trace_layer = TraceLayer::new_for_http()
    .make_span_with(|request: &Request| {
        let uri = request.uri().to_string();
        let method = request.method().to_string();

        // 自定义 span 字段
        tracing::info_span!(
            "http_request",
            method = %method,
            uri = %uri,
            status = tracing::field::Empty,     // 稍后填充
            latency_ms = tracing::field::Empty, // 稍后填充
        )
    })
    .on_response(|response: &axum::http::Response<_>, latency: Duration, span: &Span| {
        let status = response.status().as_u16();
        span.record("status", status);
        span.record("latency_ms", latency.as_millis() as u64);
        tracing::info!("response completed");
    })
    .on_failure(|error, latency: Duration, span: &Span| {
        span.record("latency_ms", latency.as_millis() as u64);
        tracing::error!(?error, "request failed");
    });

let app = Router::new()
    .route("/", get(handler))
    .layer(trace_layer);
```

---

## 📝 5. 在 Handler 中使用 tracing

### 5.1 基础宏

```rust
use tracing::{trace, debug, info, warn, error};

async fn handler() -> &'static str {
    trace!("最详细的追踪信息");
    debug!("调试信息");
    info!("一般信息");
    warn!("警告");
    error!("错误！");

    // 结构化字段
    info!(user_id = 42, action = "login", "用户登录成功");

    // 使用 ? 和 % 前缀
    let err = std::io::Error::new(std::io::ErrorKind::NotFound, "file missing");
    error!(?err, "发生IO错误");           // ?err => Debug 格式
    error!(%err, "发生IO错误");           // %err => Display 格式

    "OK"
}
```

### 5.2 `#[instrument]` 自动创建 Span

```rust
use axum::{extract::Path, Json};
use tracing::instrument;

/// 自动创建 span，包含函数名和参数
#[instrument(
    name = "get_user",           // 自定义 span 名称（默认为函数名）
    skip(db),                    // 跳过不需要记录的参数
    fields(user_id = %id),      // 自定义字段
    level = "info",              // span 级别
)]
async fn get_user(
    Path(id): Path<u64>,
    db: DatabasePool,
) -> Json<User> {
    info!("正在查询用户");   // 这条日志会自动附上 span 上下文
    let user = db.find_user(id).await;
    Json(user)
}
```

### 5.3 手动创建 Span

```rust
use tracing::{info_span, Instrument};

async fn process_order(order_id: u64) {
    let span = info_span!("process_order", order_id = %order_id);

    // 方式1: 使用 .instrument() 附加到 async 块
    async {
        info!("处理订单中...");
        // ... 业务逻辑 ...
        info!("订单处理完成");
    }
    .instrument(span)
    .await;

    // 方式2: 使用 enter()（仅限同步代码！异步中不要使用）
    let span = info_span!("sync_work");
    let _enter = span.enter();
    // ... 同步代码 ...
}
```

---

## 🏗️ 6. 生产级完整模板

```rust
use axum::{extract::Request, routing::get, Router};
use std::time::Duration;
use tower::ServiceBuilder;
use tower_http::{
    cors::{Any, CorsLayer},
    trace::{TraceLayer, DefaultMakeSpan, DefaultOnResponse},
};
use tracing::{info, Level, Span};
use tracing_subscriber::{fmt, EnvFilter, prelude::*};

fn init_tracing() -> tracing_appender::non_blocking::WorkerGuard {
    // 文件日志：按天轮转
    let file_appender = tracing_appender::rolling::daily("logs", "server.log");
    let (non_blocking_file, guard) = tracing_appender::non_blocking(file_appender);

    // 环境变量过滤器
    let env_filter = EnvFilter::try_from_default_env().unwrap_or_else(|_| {
        EnvFilter::new("info,tower_http=debug,axum=trace,my_app=debug")
    });

    tracing_subscriber::registry()
        .with(env_filter)
        // Layer 1: stdout (人类可读)
        .with(
            fmt::layer()
                .with_target(true)
                .with_level(true)
                .compact()
        )
        // Layer 2: 文件 (JSON, 供日志系统采集)
        .with(
            fmt::layer()
                .json()
                .with_writer(non_blocking_file)
                .with_thread_names(true)
                .with_span_list(true)
        )
        .init();

    guard
}

#[tokio::main]
async fn main() {
    let _guard = init_tracing();

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    let trace_layer = TraceLayer::new_for_http()
        .make_span_with(|request: &Request| {
            let matched_path = request
                .extensions()
                .get::<axum::extract::MatchedPath>()
                .map(|p| p.as_str().to_owned())
                .unwrap_or_else(|| request.uri().path().to_owned());

            tracing::info_span!(
                "http",
                method = %request.method(),
                path = %matched_path,
                status = tracing::field::Empty,
            )
        })
        .on_response(|res: &axum::http::Response<_>, latency: Duration, span: &Span| {
            span.record("status", res.status().as_u16());
            tracing::info!(latency = ?latency, "response");
        })
        .on_failure(|err, _latency: Duration, _span: &Span| {
            tracing::error!(?err, "request failed");
        });

    let middleware = ServiceBuilder::new()
        .layer(trace_layer)
        .layer(cors);

    let app = Router::new()
        .route("/", get(|| async { "Hello!" }))
        .route("/health", get(health_check))
        .layer(middleware);

    let addr = "0.0.0.0:3000";
    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    info!("🚀 Server started on {addr}");
    axum::serve(listener, app).await.unwrap();
}

async fn health_check() -> &'static str {
    info!("Health check hit");
    "OK"
}
```

---

## ⚡ 7. 常用 EnvFilter 语法速查

| 环境变量 `RUST_LOG=` | 含义 |
|---|---|
| `info` | 全局 INFO 级别 |
| `warn,my_app=debug` | 全局 WARN，`my_app` 模块 DEBUG |
| `tower_http=debug` | 只开启 tower_http 的 DEBUG |
| `my_app::api=trace` | 只开启 `my_app::api` 子模块的 TRACE |
| `info,axum=off` | 全局 INFO，关闭 axum 自身的所有日志 |
| `my_app[{user_id=42}]=debug` | 只对 `user_id=42` 的 span 启用 DEBUG |

---

## 🔑 8. 常见问题速查

| 问题 | 解决方案 |
|---|---|
| 没有日志输出 | 检查是否设置了 `RUST_LOG` 环境变量，或在代码中提供默认 `EnvFilter` |
| `tracing_appender` 日志文件为空 | `WorkerGuard` 被提前 drop 了，确保 `_guard` 保持在 `main` 作用域 |
| 异步代码 span 丢失上下文 | 不要在 async 中用 `span.enter()`，改用 `.instrument(span)` |
| 日志太多太吵 | 设置 `RUST_LOG=warn,my_app=info` 只看自己的模块 |
| 想同时兼容老的 `log` crate | `tracing` 默认自带兼容层，直接有效。或加 `tracing-log` crate |
| 想在测试中捕获日志 | 使用 `tracing_subscriber::fmt().with_test_writer().init()` |

---

## 📊 9. 日志级别参考

```
TRACE  →  最详细 (请求/响应 body, SQL 语句等)
DEBUG  →  开发调试 (变量值, 分支走向)
INFO   →  运行时关键事件 (启动, 请求完成, 任务执行)
WARN   →  可恢复的异常 (重试, 降级)
ERROR  →  错误 (请求失败, 数据库连接断开)
```

**生产环境推荐**: `RUST_LOG=info,tower_http=warn`
**开发环境推荐**: `RUST_LOG=debug,tower_http=debug,hyper=info`

---

这份 Cheatsheet 覆盖了从零配置到生产级部署的完整方案。对于大多数项目，直接使用 **第 6 节的生产级模板** 作为起点即可。如果有任何特定场景（如 OpenTelemetry 集成、自定义 Span 处理器等）需要深入，可以继续提问！
