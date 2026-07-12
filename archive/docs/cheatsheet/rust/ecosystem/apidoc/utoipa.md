# Rust 后端开发提供接口文档的方案

Rust 生态中，提供 API 接口文档主要有以下几种方案。我来为你详细介绍最主流的方式。

---

## 方案对比

| 方案 | 适配框架 | 特点 |
|------|---------|------|
| **utoipa** | Actix-web, Axum, Rocket 等 | ⭐ 最流行，通过宏自动生成 OpenAPI 文档 |
| **aide** | Axum | 专为 Axum 设计，与路由深度集成 |
| **paperclip** | Actix-web | Actix 专用，较成熟 |
| 手写 OpenAPI YAML/JSON | 任意 | 灵活但维护成本高 |

让我为你查找 **utoipa**（最主流方案）的最新用法：

非常好，下面是 Rust 后端开发中提供接口文档的 **完整指南**：

---

## 🏆 推荐方案：utoipa（最主流）

**utoipa** 是 Rust 生态中最流行的 OpenAPI 文档生成库，通过 **过程宏** 自动从代码生成 OpenAPI 3.x 文档，并搭配 Swagger UI 在线查看。

---

### 1. 添加依赖（`Cargo.toml`）

以 **Axum** 框架为例：

```toml
[dependencies]
axum = "0.8"
tokio = { version = "1", features = ["full"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"

# utoipa 核心 + Axum 集成 + Swagger UI
utoipa = { version = "5", features = ["axum_extras"] }
utoipa-axum = "0.2"
utoipa-swagger-ui = { version = "9", features = ["axum"] }
```

如果用 **Actix-web**，换成：

```toml
utoipa-swagger-ui = { version = "9", features = ["actix-web"] }
```

---

### 2. 定义数据模型（Schema）

使用 `#[derive(ToSchema)]` 宏让结构体自动生成 OpenAPI Schema：

```rust
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

/// 宠物信息
#[derive(Serialize, Deserialize, ToSchema)]
struct Pet {
    /// 宠物ID
    id: u64,
    /// 宠物名称
    name: String,
    /// 宠物年龄
    age: Option<i32>,
}

/// 创建宠物请求
#[derive(Deserialize, ToSchema)]
struct CreatePetRequest {
    /// 宠物名称
    name: String,
    /// 宠物年龄
    age: Option<i32>,
}

/// 通用响应
#[derive(Serialize, ToSchema)]
struct ApiResponse<T: ToSchema> {
    code: i32,
    message: String,
    data: Option<T>,
}
```

> 💡 **关键**：Rust 的 `///` 文档注释会自动成为 OpenAPI 的字段描述！

---

### 3. 定义 API 接口（Path）

使用 `#[utoipa::path]` 宏标注每个接口的元信息：

```rust
use axum::{extract::Path, Json};
use utoipa::OpenApi;

/// 根据 ID 获取宠物
///
/// 从数据库中根据宠物 ID 查询宠物信息
#[utoipa::path(
    get,
    path = "/pets/{id}",
    tag = "宠物管理",
    params(
        ("id" = u64, Path, description = "宠物 ID"),
    ),
    responses(
        (status = 200, description = "查询成功", body = Pet),
        (status = 404, description = "宠物不存在")
    )
)]
async fn get_pet_by_id(Path(id): Path<u64>) -> Json<Pet> {
    Json(Pet {
        id,
        name: "小白".to_string(),
        age: Some(3),
    })
}

/// 创建宠物
///
/// 创建一个新的宠物记录
#[utoipa::path(
    post,
    path = "/pets",
    tag = "宠物管理",
    request_body(
        content = CreatePetRequest, 
        description = "宠物信息",
        content_type = "application/json"
    ),
    responses(
        (status = 201, description = "创建成功", body = Pet,
            example = json!({"id": 1, "name": "小白", "age": 3})
        ),
        (status = 400, description = "参数错误")
    ),
    // 可选：接口安全认证
    security(
        ("bearer_token" = [])
    )
)]
async fn create_pet(Json(req): Json<CreatePetRequest>) -> Json<Pet> {
    Json(Pet {
        id: 1,
        name: req.name,
        age: req.age,
    })
}

/// 获取所有宠物
#[utoipa::path(
    get,
    path = "/pets",
    tag = "宠物管理",
    params(
        ("page" = Option<u32>, Query, description = "页码"),
        ("size" = Option<u32>, Query, description = "每页数量"),
    ),
    responses(
        (status = 200, description = "查询成功", body = Vec<Pet>)
    )
)]
async fn list_pets() -> Json<Vec<Pet>> {
    Json(vec![])
}
```

---

### 4. 组装路由并挂载 Swagger UI

#### 方式一：使用 `OpenApiRouter`（推荐，自动收集路由）

```rust
use utoipa::OpenApi;
use utoipa_axum::{router::OpenApiRouter, routes};
use utoipa_swagger_ui::SwaggerUi;

#[derive(OpenApi)]
#[openapi(
    info(
        title = "宠物商店 API",
        version = "1.0.0",
        description = "这是一个示例宠物商店接口文档"
    ),
    // 可选：定义安全方案
    // security(
    //     ("bearer_token" = [])
    // ),
    // components(
    //     security_schemes(
    //         ("bearer_token" = SecurityScheme::Http(
    //             HttpBuilder::new().scheme(HttpAuthScheme::Bearer).bearer_format("JWT").build()
    //         ))
    //     )
    // )
)]
struct ApiDoc;

#[tokio::main]
async fn main() {
    // ✅ OpenApiRouter 自动收集路由 + 生成文档
    let (router, api) = OpenApiRouter::with_openapi(ApiDoc::openapi())
        .routes(routes!(get_pet_by_id))
        .routes(routes!(create_pet))
        .routes(routes!(list_pets))
        .split_for_parts();

    // 挂载 Swagger UI
    let app = router.merge(
        SwaggerUi::new("/swagger-ui")
            .url("/api-docs/openapi.json", api)
    );

    let listener = tokio::net::TcpListener::bind("0.0.0.0:3000").await.unwrap();
    println!("📖 Swagger UI: http://localhost:3000/swagger-ui/");
    axum::serve(listener, app).await.unwrap();
}
```

#### 方式二：手动注册（传统方式）

```rust
#[derive(OpenApi)]
#[openapi(
    paths(get_pet_by_id, create_pet, list_pets),  // 手动列出所有接口
    components(schemas(Pet, CreatePetRequest)),     // 手动列出所有 Schema
    info(title = "宠物商店 API", version = "1.0.0")
)]
struct ApiDoc;
```

---

### 5. 效果

启动服务后访问：

| 地址 | 说明 |
|------|------|
| `http://localhost:3000/swagger-ui/` | 📖 **Swagger UI** 交互式文档界面 |
| `http://localhost:3000/api-docs/openapi.json` | 📄 OpenAPI JSON 规范文件 |

Swagger UI 界面可以直接 **在线调试接口**，非常方便前后端联调。

---

### 6. 高级用法速查

#### 🔐 安全认证（JWT Bearer）

```rust
use utoipa::openapi::security::{HttpAuthScheme, HttpBuilder, SecurityScheme};

#[derive(OpenApi)]
#[openapi(
    components(schemas(Pet)),
    modifiers(&SecurityAddon)
)]
struct ApiDoc;

struct SecurityAddon;

impl utoipa::Modify for SecurityAddon {
    fn modify(&self, openapi: &mut utoipa::openapi::OpenApi) {
        let components = openapi.components.as_mut().unwrap();
        components.add_security_scheme(
            "bearer_token",
            SecurityScheme::Http(
                HttpBuilder::new()
                    .scheme(HttpAuthScheme::Bearer)
                    .bearer_format("JWT")
                    .build()
            ),
        );
    }
}
```

#### 📦 枚举类型

```rust
#[derive(Serialize, ToSchema)]
enum PetStatus {
    Available,
    Pending,
    Sold,
}
```

#### 🏷️ 分组 Tag

```rust
#[utoipa::path(
    get,
    path = "/users",
    tag = "用户管理",   // 接口分组
    // ...
)]
```

---

### 7. 完整项目结构参考

```
my-api/
├── Cargo.toml
└── src/
    ├── main.rs          # 启动入口 + Swagger 挂载
    ├── routes/
    │   ├── mod.rs
    │   └── pets.rs      # 宠物相关接口 (#[utoipa::path])
    ├── models/
    │   ├── mod.rs
    │   └── pet.rs       # 数据模型 (#[derive(ToSchema)])
    └── doc.rs           # OpenApi 定义 + SecurityAddon
```

---

## 总结

| 步骤 | 做什么 |
|------|--------|
| ① | 给结构体加 `#[derive(ToSchema)]` |
| ② | 给接口函数加 `#[utoipa::path(...)]` |
| ③ | 用 `#[derive(OpenApi)]` 汇总注册 |
| ④ | 挂载 `SwaggerUi` 到路由 |

这套方案的核心优势是 **文档即代码**——接口文档直接从代码生成，避免了手写文档和代码不同步的问题。修改了接口代码，文档自动更新。
