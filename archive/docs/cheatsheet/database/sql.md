# PostgreSQL (含 SQLite 笔记) 速查表

## 1. 📦 环境与起手式

### 安装 (Docker)

```bash
# PostgreSQL
docker run --name some-postgres -e POSTGRES_PASSWORD=mysecretpassword -d -p 5432:5432 postgres:16-alpine

# SQLite (无需安装，仅需文件)
# sudo apt-get install sqlite3
```

### 导入 / 驱动

```python
# Python (PG 使用 psycopg2, SQLite 使用 sqlite3)
import psycopg2
conn = psycopg2.connect("dbname=test user=postgres password=secret host=localhost")

import sqlite3
conn = sqlite3.connect('example.db')
```

### 连接字符串 (URI)

```text
postgresql://user:password@localhost:5432/dbname
sqlite:///relative/path/to/file.db
```

### 最小化配置 (`postgresql.conf` / `pg_hba.conf`)

- `listen_addresses = '*'` (允许远程连接)
- `host all all 0.0.0.0/0 md5` (允许来自任何 IP 的身份验证)

## 2. ⚡️ 核心语法 / API

| 特性 | PostgreSQL | SQLite | 备注 |
| :--- | :--- | :--- | :--- |
| **Serial/Auto Inc** | `SERIAL` / `GENERATED ALWAYS AS IDENTITY` | `INTEGER PRIMARY KEY` | SQLite `AUTOINCREMENT` 很少需要。 |
| **JSON** | `JSONB` (二进制, 可索引) | `TEXT` (提供 JSON 函数) | PG 的 `JSONB` 在查询性能上更优。 |
| **Boolean** | `BOOLEAN` (`TRUE`/`FALSE`) | `INTEGER` (0/1) | SQLite 没有原生布尔类型。 |
| **Date/Time** | `TIMESTAMPTZ`, `DATE`, `INTERVAL` | `TEXT` / `REAL` / `INTEGER` | SQLite 将日期存储为字符串/数字。 |
| **Array** | `TEXT[]`, `INTEGER[]` | 不支持 | 在 SQLite 中存储为 JSON 或关联表。 |

### 语法糖 (PostgreSQL)

```sql
-- 类型转换
SELECT '123'::INTEGER;

-- 字符串拼接
SELECT 'Hello' || ' ' || 'World';

-- ILIKE (忽略大小写)
SELECT * FROM users WHERE name ILIKE 'john%';

-- 从 Insert/Update 返回数据
INSERT INTO users (name) VALUES ('Jane') RETURNING id, created_at;
```

## 3. 🛠 命令行与工具链

### `psql` (PostgreSQL)

```bash
# 连接
psql -h localhost -U postgres -d dbname

# 常用元命令
\l        # 列出数据库
\c dbname # 连接到数据库
\dt       # 列出表
\d table  # 查看表结构
\du       # 列出用户/角色
\x        # 切换扩展显示模式 (自动垂直输出)
\q        # 退出
```

### `sqlite3` (SQLite)

```bash
# 连接
sqlite3 data.db

# 常用点命令
.databases  # 列出已连接的数据库
.tables     # 列出表
.schema tab # 显示表的 CREATE 语句
.mode box   # 更好的输出格式
.headers on # 显示表头
.quit       # 退出
```

### 备份与恢复

```bash
# PG 备份与恢复
pg_dump -h localhost -U user dbname > dump.sql
psql -h localhost -U user dbname < dump.sql

# SQLite 备份
sqlite3 data.db ".backup backup.db"
```

### DBeaver (GUI)

- **防手滑模式 (Manual Commit)**:
  - 默认 `Auto-Commit` (自动提交) 极其危险。
  - **设置**: 工具栏点击 `Tx` / `Auto` -> 切换为 `Manual Commit` (手动提交)。
  - **流程**: `执行` -> `验证` -> `Commit` (提交) 或 `Rollback` (回滚)。
- **常用快捷键**:
  - `Ctrl + Enter`: 执行当前语句
  - `Ctrl + Alt + Shift + X`: 执行脚本

## 4. 💡 高频代码片段

### 安全事务 (Safe Update)

**场景**: 确保 UPDATE/DELETE 可撤销。

```sql
BEGIN; -- 开启事务 (DBeaver: 切换为 Manual Commit)

-- 1. 执行修改
UPDATE material_items SET ...;

-- 2. 验证结果
SELECT * FROM material_items WHERE ...;

-- 3. 提交或回滚
-- COMMIT;   -- 确认
-- ROLLBACK; -- 撤销
```

### UPSERT (插入或更新)

**场景**: 插入记录，如果 ID 已存在，则更新 email。

```sql
-- PostgreSQL (ON CONFLICT)
INSERT INTO users (id, email) VALUES (1, 'new@example.com')
ON CONFLICT (id) 
DO UPDATE SET email = EXCLUDED.email, updated_at = NOW();

-- SQLite (ON CONFLICT / UPSERT - 现代 SQLite)
INSERT INTO users (id, email) VALUES (1, 'new@example.com')
ON CONFLICT(id) 
DO UPDATE SET email = excluded.email;
```

### CTE (公用表表达式)

**场景**: 提高复杂查询的可读性 / 递归查询。

```sql
WITH regional_sales AS (
    SELECT region, SUM(amount) as total_sales
    FROM orders
    GROUP BY region
)
SELECT * FROM regional_sales WHERE total_sales > (SELECT SUM(total_sales)/10 FROM regional_sales);
```

### JSONB 查询 (PostgreSQL 特有)

**场景**: 查询嵌套的 JSON 数据。

```sql
-- 通过键选择值 'info' -> 'tags' (数组) -> 0
SELECT data->'info'->'tags'->>0 FROM products;

-- 检查 JSON 是否包含键值对 @>
SELECT * FROM products WHERE data @> '{"category": "electronics"}';

-- 检查键是否存在 ?
SELECT * FROM products WHERE data ? 'sku';
```

### 日期计算

**场景**: 查找过去 7 天内创建的记录。

```sql
-- PostgreSQL
SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '7 days';

-- SQLite
SELECT * FROM orders WHERE created_at > date('now', '-7 days');
```

## 5. ⚠️ 避坑与最佳实践

### 反模式与修复

- ❌ **在生产环境使用 `*`**: `SELECT * FROM users` -> 如果列发生变化会导致错误。
  - ✅ **明确指定列**: `SELECT id, name FROM users`。
- ❌ **未加引号的标识符 (混合大小写)**: PG 会将未加引号的标识符转换为小写。`Create Table User` -> `user`。
  - ✅ **蛇形命名法 (Snake_case)**: 使用 `user_accounts` 而不是 `UserAccounts`。
- ❌ **使用浮点数存储金额**: 会产生精度误差。
  - ✅ **使用 `DECIMAL` / `NUMERIC`**: `NUMERIC(10, 2)`。

### 性能优化

- **索引外键 (FK)**: 外键**不会**被自动索引。为了连接性能，请手动创建索引。
- **Explain**: 始终在慢查询上运行 `EXPLAIN ANALYZE`。
- **事务 (Transactions)**: 将多个写入操作封装在 `BEGIN; ... COMMIT;` 中。

### SQLite 特定注意事项

- **并发性**: SQLite 每次只允许一个写入者 (数据库锁)。启用 WAL 模式以获得更好的并发性能:

  ```sql
  PRAGMA journal_mode=WAL;
  ```

- **弱类型**: 你可以在整型列中存储文本 (大多数情况下)。请务必小心。

## 6. 🔎 调试与排查

### 查询分析

```sql
-- PostgreSQL
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM large_table WHERE id = 100;

-- SQLite
EXPLAIN QUERY PLAN SELECT * FROM large_table WHERE id = 100;
```

### 当前活动 (PostgreSQL)

```sql
-- 谁在连接？他们在做什么？
SELECT pid, usename, state, query 
FROM pg_stat_activity 
WHERE state != 'idle';

-- 终止查询 (使用上面的 pid)
SELECT pg_terminate_backend(pid);
```

### 锁 (PostgreSQL)

```sql
SELECT t.relname, l.locktype, page, virtualtransaction, pid, mode, granted 
FROM pg_locks l, pg_stat_all_tables t 
WHERE l.relation = t.relid ORDER BY relation ASC;
```

### 结构检查

```sql
-- PG: 检查表大小
SELECT pg_size_pretty(pg_total_relation_size('my_table'));

-- SQLite: 检查完整性
PRAGMA integrity_check;
```

## 7. 📊 聚合与统计 (Aggregation & Statistics)

### 基础聚合函数

```sql
SELECT 
    COUNT(*) as total_rows,          -- 总行数
    COUNT(column) as non_null_count, -- 非空行数
    SUM(price) as total_price,       -- 求和
    AVG(score) as average_score,     -- 平均值
    MAX(created_at) as latest,       -- 最大值
    MIN(amount) as minimum           -- 最小值
FROM orders;
```

### 分组过滤 (GROUP BY & HAVING)

**场景**: 统计每个类别的订单数，并筛选出订单数大于 5 的类别。

```sql
SELECT category, COUNT(*) as count
FROM products
GROUP BY category
HAVING COUNT(*) > 5
ORDER BY count DESC;
```

### 窗口函数 (Window Functions - PG 强项)

**场景**: 在不合并行的情况下计算排名或累计总和。

```sql
-- 计算每个部门内员工的薪资排名
SELECT 
    name, 
    dept, 
    salary,
    RANK() OVER (PARTITION BY dept ORDER BY salary DESC) as salary_rank,
    SUM(salary) OVER (PARTITION BY dept) as dept_total_budget
FROM employees;
```

### 差异提示 (PostgreSQL vs SQLite)

- **Distinct Count**:
  - PG/SQLite 均支持 `COUNT(DISTINCT column)`。
- **Median (中位数)**:
  - PostgreSQL: `PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY column)`。
  - SQLite: 无原生中位数函数，需使用 CTE 或扩展。
- **String Aggregation (字符串聚合)**:
  - PostgreSQL: `STRING_AGG(name, ', ')`。
  - SQLite: `GROUP_CONCAT(name, ', ')`。
