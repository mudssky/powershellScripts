
---

## SeaORM 完整使用指南

SeaORM 是 Rust 中最成熟的**异步 ORM**，底层基于 `sqlx`，核心优势是：

- **一套 Rust 代码，自动适配 PostgreSQL / MySQL / SQLite**
- **迁移脚本也用 Rust 写，跨数据库通用**
- **运行时仅通过修改连接 URL 即可切换数据库**

---

### 一、项目初始化

#### 1. 安装 CLI 工具

SeaORM 提供了一个强大的命令行工具 `sea-orm-cli`，用于迁移管理和从数据库生成实体代码：

```bash
cargo install sea-orm-cli
```

#### 2. 添加依赖

在 `Cargo.toml` 中添加：

```toml
[dependencies]
sea-orm = { version = "1.1", features = [
    "sqlx-postgres",     # PostgreSQL 支持
    "sqlx-sqlite",       # SQLite 支持
    "runtime-tokio-rustls",
    "macros",
] }
tokio = { version = "1", features = ["full"] }
```

#### 3. 连接数据库

```rust
use sea_orm::Database;

#[tokio::main]
async fn main() -> Result<(), sea_orm::DbErr> {
    // 只需要改这一行 URL，就能切换数据库！
    let db_url = "postgres://user:pass@localhost/my_db";
    // let db_url = "sqlite://./my_db.sqlite?mode=rwc";

    let db = Database::connect(db_url).await?;
    println!("数据库连接成功！");

    Ok(())
}
```

SeaORM 会自动根据 URL 前缀（`postgres://` / `sqlite://` / `mysql://`）选择对应的驱动，**零额外配置**。

---

### 二、数据库迁移（Migration）

这是 SeaORM 最强大的地方之一：**迁移脚本是用 Rust 代码写的**，而不是原生 SQL。这意味着一套迁移代码可以自动适配所有数据库！

#### 1. 初始化迁移目录

在项目根目录执行：

```bash
sea-orm-cli migrate init
```

这会生成一个 `migration/` 子目录，结构如下：

```
migration/
├── Cargo.toml
├── src/
│   ├── lib.rs
│   ├── main.rs
│   └── m20220101_000001_create_table.rs   # 示例迁移文件
```

`migration/` 本身是一个独立的 Rust crate。

#### 2. 创建新的迁移

```bash
sea-orm-cli migrate generate create_users_table
```

这会在 `migration/src/` 下生成一个新文件，例如 `m20231025_120000_create_users_table.rs`。

#### 3. 编写迁移代码（核心！）

打开生成的文件，用 SeaORM 提供的 Schema Builder API 来定义表结构：

```rust
// migration/src/m20231025_120000_create_users_table.rs

use sea_orm_migration::{prelude::*, schema::*};

#[derive(DeriveMigrationName)]
pub struct Migration;

#[async_trait::async_trait]
impl MigrationTrait for Migration {
    // 正向迁移：建表
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .create_table(
                Table::create()
                    .table(Users::Table)
                    .if_not_exists()
                    .col(pk_auto(Users::Id))                    // 自增主键
                    .col(string_uniq(Users::Username))          // 唯一字符串
                    .col(string(Users::Email))                  // 普通字符串
                    .col(boolean(Users::IsActive))              // 布尔值
                    .col(
                        ColumnDef::new(Users::CreatedAt)
                            .timestamp_with_time_zone()
                            .not_null()
                            .default(Expr::current_timestamp()),
                    )
                    .to_owned(),
            )
            .await
    }

    // 反向迁移：删表
    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        manager
            .drop_table(Table::drop().table(Users::Table).to_owned())
            .await
    }
}

// 用枚举定义表名和列名，避免硬编码字符串
#[derive(DeriveIden)]
enum Users {
    Table,
    Id,
    Username,
    Email,
    IsActive,
    CreatedAt,
}
```

> **注意看：整个迁移文件里没有一句原生 SQL！**
> `pk_auto()` 在 Postgres 下生成 `SERIAL PRIMARY KEY`，在 SQLite 下生成 `INTEGER PRIMARY KEY AUTOINCREMENT`。
> `boolean()` 在 Postgres 下生成 `BOOLEAN`，在 SQLite 下生成 `INTEGER`。
> SeaORM 全部帮你翻译了。

#### 4. 注册迁移

在 `migration/src/lib.rs` 中注册你的新迁移：

```rust
pub use sea_orm_migration::prelude::*;

mod m20231025_120000_create_users_table;

pub struct Migrator;

#[async_trait::async_trait]
impl MigratorTrait for Migrator {
    fn migrations() -> Vec<Box<dyn MigrationTrait>> {
        vec![
            Box::new(m20231025_120000_create_users_table::Migration),
            // 未来有新的迁移，按顺序追加到这里
        ]
    }
}
```

#### 5. 运行迁移

```bash
# 执行所有未执行的迁移
sea-orm-cli migrate up

# 回滚上一个迁移
sea-orm-cli migrate down

# 查看迁移状态
sea-orm-cli migrate status
```

你也可以在 Rust 代码中启动时自动运行迁移：

```rust
use migration::{Migrator, MigratorTrait};

// 在 main 函数中
Migrator::up(&db, None).await?;
```

---

### 三、生成实体（Entity）

SeaORM 可以**直接从数据库里反向生成 Rust 实体代码**。这比手写省力太多了。

确保迁移已执行（表已经存在于数据库中），然后运行：

```bash
sea-orm-cli generate entity \
    -u "postgres://user:pass@localhost/my_db" \
    -o src/entities
```

这会在 `src/entities/` 下自动生成文件：

```
src/entities/
├── mod.rs
├── prelude.rs
└── users.rs        # 从数据库的 users 表自动生成
```

生成的 `users.rs` 大致如下（自动生成，不需要手写）：

```rust
// src/entities/users.rs （自动生成）

use sea_orm::entity::prelude::*;

#[derive(Clone, Debug, PartialEq, DeriveEntityModel)]
#[sea_orm(table_name = "users")]
pub struct Model {
    #[sea_orm(primary_key)]
    pub id: i32,
    #[sea_orm(unique)]
    pub username: String,
    pub email: String,
    pub is_active: bool,
    pub created_at: DateTimeWithTimeZone,
}

#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {}

impl ActiveModelBehavior for ActiveModel {}
```

---

### 四、CRUD 操作

在项目代码中引入实体：

```rust
mod entities;
use entities::{prelude::*, users};
use sea_orm::*;
```

#### 1. 插入（Create）

```rust
// 插入一条
let new_user = users::ActiveModel {
    username: Set("alice".to_owned()),
    email: Set("alice@example.com".to_owned()),
    is_active: Set(true),
    ..Default::default()  // id 和 created_at 使用默认值
};
let result = Users::insert(new_user).exec(&db).await?;
println!("插入成功，ID: {}", result.last_insert_id);

// 批量插入
let bob = users::ActiveModel {
    username: Set("bob".to_owned()),
    email: Set("bob@example.com".to_owned()),
    is_active: Set(true),
    ..Default::default()
};
let charlie = users::ActiveModel {
    username: Set("charlie".to_owned()),
    email: Set("charlie@example.com".to_owned()),
    is_active: Set(false),
    ..Default::default()
};
Users::insert_many([bob, charlie]).exec(&db).await?;
```

#### 2. 查询（Read）

```rust
// 查询所有
let all_users: Vec<users::Model> = Users::find().all(&db).await?;

// 根据主键查询
let user: Option<users::Model> = Users::find_by_id(1).one(&db).await?;

// 条件查询
let active_users: Vec<users::Model> = Users::find()
    .filter(users::Column::IsActive.eq(true))
    .order_by_asc(users::Column::Username)
    .limit(10)
    .all(&db)
    .await?;

// 复杂条件
let result = Users::find()
    .filter(
        Condition::any()
            .add(users::Column::Username.contains("ali"))
            .add(users::Column::Email.ends_with("@example.com"))
    )
    .all(&db)
    .await?;
```

#### 3. 更新（Update）

```rust
// 先查出来，再修改
let user: users::Model = Users::find_by_id(1).one(&db).await?.unwrap();

// 将 Model 转换为 ActiveModel（可编辑状态）
let mut user: users::ActiveModel = user.into();
user.email = Set("new_email@example.com".to_owned());

// 保存更新
let updated_user: users::Model = user.update(&db).await?;
```

#### 4. 删除（Delete）

```rust
// 根据主键删除
Users::delete_by_id(1).exec(&db).await?;

// 条件删除
Users::delete_many()
    .filter(users::Column::IsActive.eq(false))
    .exec(&db)
    .await?;
```

---

### 五、定义表关联（Relations）

SeaORM 支持一对多、多对多等关联。例如，用户有多篇文章：

```rust
// 在 users.rs 中定义关联
#[derive(Copy, Clone, Debug, EnumIter, DeriveRelation)]
pub enum Relation {
    #[sea_orm(has_many = "super::posts::Entity")]
    Posts,
}

impl Related<super::posts::Entity> for Entity {
    fn to() -> RelationDef {
        Relation::Posts.def()
    }
}
```

查询关联数据：

```rust
// 查询用户及其所有文章
let user_with_posts: Vec<(users::Model, Vec<posts::Model>)> = Users::find()
    .find_with_related(Posts)
    .all(&db)
    .await?;

for (user, posts) in user_with_posts {
    println!("用户 {} 有 {} 篇文章", user.username, posts.len());
}
```

---

### 六、事务（Transaction）

```rust
let txn = db.begin().await?;

let user = users::ActiveModel {
    username: Set("dave".to_owned()),
    email: Set("dave@example.com".to_owned()),
    is_active: Set(true),
    ..Default::default()
};
let user = user.insert(&txn).await?;

// 如果这里出错，整个事务自动回滚
let post = posts::ActiveModel {
    title: Set("Hello World".to_owned()),
    user_id: Set(user.id),
    ..Default::default()
};
post.insert(&txn).await?;

// 一切正常，提交事务
txn.commit().await?;
```

---

### 总结：完整项目结构

```
my_project/
├── Cargo.toml
├── .env                          # DATABASE_URL=postgres://...
├── migration/                    # 迁移 crate（Rust 代码写的，跨库通用）
│   ├── Cargo.toml
│   └── src/
│       ├── lib.rs
│       ├── main.rs
│       └── m20231025_create_users_table.rs
├── src/
│   ├── main.rs                   # 连接数据库 + 自动迁移 + 业务逻辑
│   └── entities/                 # 自动生成的实体代码
│       ├── mod.rs
│       ├── prelude.rs
│       └── users.rs
```

### 标准开发流程

1. **改表结构时：** `sea-orm-cli migrate generate <name>` → 用 Rust 代码写迁移 → `sea-orm-cli migrate up`
2. **生成实体：** `sea-orm-cli generate entity -o src/entities`
3. **写业务：** 直接使用生成的实体进行 CRUD，所有 SQL 方言差异由 SeaORM 自动处理
4. **切换数据库：** 只需改 `.env` 里的 `DATABASE_URL`，代码一行不动
