### Prisma 全流程速查表 (Cheatsheet)

本文档涵盖了使用 Prisma 的完整生命周期：从项目初始化、定义数据模型、数据库迁移，到在应用程序中使用 Prisma Client 进行数据操作。

#### **第 1 部分：安装与项目初始化**

1. **安装依赖**
    * `prisma`: 命令行工具 (CLI)，作为开发依赖。
    * `@prisma/client`: 在应用代码中使用的客户端库。

    ```bash
    npm install prisma --save-dev
    npm install @prisma/client
    ```

2. **初始化项目**

    * 此命令会创建 `prisma` 文件夹，并在其中生成 `schema.prisma` 文件，同时还会创建一个 `.env` 文件用于存放数据库连接字符串。

    ```bash
    npx prisma init
    ```

    * **`schema.prisma` 初始内容:**

        ```prisma
        generator client {
          provider = "prisma-client-js"
        }
    
        datasource db {
          provider = "postgresql" // 可选: postgresql, mysql, sqlite, sqlserver, mongodb, cockroachdb
          url      = env("DATABASE_URL")
        }
        ```

    * **`.env` 初始内容:**

        ```env
        # 示例 PostgreSQL 连接字符串
        DATABASE_URL="postgresql://USER:PASSWORD@HOST:PORT/DATABASE?schema=public"
        ```

---

#### **第 2 部分：Schema 定义 (`schema.prisma`)**

这是 Prisma 的核心，您在这里用一种简单的语言定义您的数据模型。

##### **基本模型与字段类型**

```prisma
model Post {
  id        String   @id @default(cuid()) // 主键, 默认为 cuid
  title     String
  content   String?  // '?' 表示可选字段
  published Boolean  @default(false)
  views     Int      @default(0)
  createdAt DateTime @default(now()) // 创建时自动填充当前时间
  updatedAt DateTime @updatedAt     // 更新时自动更新时间戳
}
```

##### **常用字段属性 (`@`)**

| 属性 | 作用 |
| :--- | :--- |
| `@id` | 定义主键。 |
| `@default(...)` | 设置默认值，如 `cuid()`, `uuid()`, `now()`, `autoincrement()`。 |
| `@unique` | 定义唯一约束。 |
| `@updatedAt` | 每次记录更新时，自动更新该字段的时间戳。 |
| `@relation(...)` | 定义模型间的关系。 |
| `@map("...")` | 将字段映射到数据库中不同名称的列。 |

##### **枚举 (Enums)**

```prisma
enum Role {
  USER
  ADMIN
}

model User {
  id   String @id @default(cuid())
  role Role   @default(USER) // 使用枚举类型
}
```

##### **关系 (Relations)**

* **一对一 (1-to-1):** 用户与资料

    ```prisma
    model User {
      id      String   @id @default(cuid())
      profile Profile? // 反向关系，可选
    }

    model Profile {
      id     String @id @default(cuid())
      bio    String
      user   User   @relation(fields: [userId], references: [id])
      userId String @unique // 外键，且必须唯一
    }
    ```

* **一对多 (1-to-n):** 用户与多篇文章

    ```prisma
    model User {
      id    String @id @default(cuid())
      name  String
      posts Post[] // 一个用户可以有多篇文章
    }

    model Post {
      id        String @id @default(cuid())
      title     String
      author    User   @relation(fields: [authorId], references: [id])
      authorId  String // 外键
    }
    ```

* **多对多 (m-n):** 文章与多个分类 (使用显式关联表)

    ```prisma
    model Post {
      id         String             @id @default(cuid())
      title      String
      categories CategoriesOnPosts[] // 关联到中间表
    }
    
    model Category {
      id    String             @id @default(cuid())
      name  String
      posts CategoriesOnPosts[] // 关联到中间表
    }
    
    // 中间表 (Join Table)
    model CategoriesOnPosts {
      post       Post     @relation(fields: [postId], references: [id])
      postId     String
      category   Category @relation(fields: [categoryId], references: [id])
      categoryId String
      assignedAt DateTime @default(now())
    
      @@id([postId, categoryId]) // 复合主键
    }
    ```

##### **块级属性 (`@@`)**

| 属性 | 作用 |
| :--- | :--- |
| `@@id([...])` | 定义复合主键。 |
| `@@unique([...])` | 定义复合唯一约束。 |
| `@@index([...])` | 定义数据库索引，提升查询性能。 |
| `@@map("...")` | 将模型映射到数据库中不同名称的表。 |

---

#### **第 3 部分：数据库迁移**

1. **开发中的迁移（最常用）**
    * 此命令会：
        1. 在 `prisma/migrations` 中创建一个新的 SQL 迁移文件。
        2. 将迁移应用到数据库。
        3. 重新生成 Prisma Client，使其与新的 schema 保持同步。

    ```bash
    # 第一次迁移
    npx prisma migrate dev --name init
    
    # 后续迁移
    npx prisma migrate dev --name added_user_model
    ```

2. **生产环境部署**
    * 此命令只应用待执行的迁移，不会尝试创建或修改迁移文件。

    ```bash
    npx prisma migrate deploy
    ```

3. **其他常用迁移命令**
    * `npx prisma db push`: （不推荐用于生产）快速同步 schema 到数据库，但不创建迁移文件。适合原型开发。
    * `npx prisma migrate reset`: 重置数据库，并重新应用所有迁移。**会删除所有数据！**

---

#### **第 4 部分：Prisma Client 数据操作**

##### **初始化客户端**

```typescript
import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();
// 可选配置: const prisma = new PrismaClient({ log: ['query'] }); // 打印所有查询语句
```

##### **CRUD 操作示例 (以 `Post` 模型为例)**

* **Create (创建)**

    ```typescript
    const newPost = await prisma.post.create({
      data: {
        title: 'Hello Prisma',
        content: 'This is my first post.',
        author: {
          connect: { id: 'user_cuid_123' }, // 关联到一个已存在的用户
        },
      },
    });
    ```

* **Read (查询)**
  * **查询单个**:

        ```typescript
        const post = await prisma.post.findUnique({
          where: { id: 'post_cuid_abc' },
          include: { author: true }, // 同时加载关联的 author 数据
        });
        ```    *   **查询列表**:
        ```typescript
        const posts = await prisma.post.findMany({
          where: {
            published: true,
            title: { contains: 'Prisma' },
          },
          orderBy: { createdAt: 'desc' },
          take: 10, // 取10条
          skip: 20, // 跳过20条 (用于分页)
        });
        ```

* **Update (更新)**

    ```typescript
    const updatedPost = await prisma.post.update({
      where: { id: 'post_cuid_abc' },
      data: {
        published: true,
        views: {
          increment: 1, // 原子操作，自增1
        },
      },
    });
    ```

* **Upsert (更新或创建)**

    ```typescript
    const post = await prisma.post.upsert({
      where: { id: 'some_id_that_may_not_exist' },
      update: { title: 'Updated Title' },
      create: { id: 'some_id_that_may_not_exist', title: 'New Post', authorId: 'user_id' },
    });
    ```

* **Delete (删除)**

    ```typescript
    const deletedPost = await prisma.post.delete({
      where: { id: 'post_cuid_abc' },
    });
    ```

##### **高级查询**

* **关系过滤**: 查询所有至少有一篇已发布文章的用户。

    ```typescript
    const users = await prisma.user.findMany({
      where: {
        posts: {
          some: { published: true }, // some, every, none
        },
      },
    });
    ```

* **事务 (Transactions)**: 保证所有操作要么全部成功，要么全部失败。

    ```typescript
    const [user1, user2] = await prisma.$transaction([
      prisma.user.update({ where: { id: 'id1' }, data: { balance: { decrement: 100 } } }),
      prisma.user.update({ where: { id: 'id2' }, data: { balance: { increment: 100 } } }),
    ]);
    ```

---

#### **第 5 部分：工作流与其他工具**

1. **数据填充 (Seeding)**
    * 在 `package.json` 中添加:

        ```json
        "prisma": {
          "seed": "ts-node prisma/seed.ts"
        }
        ```

    * 创建 `prisma/seed.ts` 文件，并在其中使用 Prisma Client 创建初始数据。
    * 运行 `npx prisma db seed`。

2. **Prisma Studio (可视化数据库编辑器)**
    * 启动一个本地的、可视化的数据库管理界面。非常适合调试和快速查看数据。

    ```bash
    npx prisma studio
    ```

3. **从现有数据库生成 Schema (Introspection)**
    * 如果你的数据库已经存在，此命令会读取数据库结构，并自动生成 `schema.prisma` 文件。

    ```bash
    npx prisma db pull
    ```
