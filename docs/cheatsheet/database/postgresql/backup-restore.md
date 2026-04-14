# PostgreSQL 备份 / 恢复 Cheat Sheet

## 0. 先记住 4 条

- **备份单个数据库**：`pg_dump`
- **恢复 `.dump/.backup/.tar/目录`**：`pg_restore`
- **恢复 `.sql`**：`psql`
- **备份整个实例（所有库 + 角色/表空间）**：`pg_dumpall`

---

## 1. 最常用场景

### 1.1 备份单个数据库（推荐：custom 格式）

```bash
pg_dump -h 127.0.0.1 -p 5432 -U postgres -d mydb -Fc -f "D:\backup\mydb.dump"
```

**说明**

- `-Fc` = custom 格式，最推荐
- 优点：可压缩、可选择性恢复、支持 `pg_restore`

---

### 1.2 恢复到一个新数据库

先建库：

```bash
createdb -h 127.0.0.1 -p 5432 -U postgres mydb_restore
```

再恢复：

```bash
pg_restore -h 127.0.0.1 -p 5432 -U postgres -d mydb_restore "D:\backup\mydb.dump"
```

---

### 1.3 恢复并覆盖已有对象

```bash
pg_restore -h 127.0.0.1 -p 5432 -U postgres -d mydb_restore --clean --if-exists "D:\backup\mydb.dump"
```

**说明**

- `--clean`：先 drop 再重建
- `--if-exists`：避免对象不存在时报错

---

## 2. SQL 文本格式

### 2.1 备份为 `.sql`

```bash
pg_dump -h 127.0.0.1 -p 5432 -U postgres -d mydb -Fp -f "D:\backup\mydb.sql"
```

### 2.2 恢复 `.sql`

```bash
createdb -h 127.0.0.1 -p 5432 -U postgres mydb_restore
psql -h 127.0.0.1 -p 5432 -U postgres -d mydb_restore -v ON_ERROR_STOP=1 -f "D:\backup\mydb.sql"
```

**注意**

- `.sql` 用 `psql`
- 不要用 `pg_restore` 恢复 `.sql`

---

## 3. 备份格式怎么选

| 格式 | 参数 | 特点 | 恢复工具 |
|---|---|---|---|
| plain SQL | `-Fp` | 可读、可编辑 | `psql` |
| custom | `-Fc` | 最常用，支持选择性恢复 | `pg_restore` |
| directory | `-Fd` | 支持并行备份/恢复，适合大库 | `pg_restore` |
| tar | `-Ft` | 较少用 | `pg_restore` |

**默认推荐**

- 日常：`-Fc`
- 大库 / 追求速度：`-Fd`
- 想直接看 SQL：`-Fp`

---

## 4. 并行备份 / 恢复

### 4.1 并行备份（directory 格式）

```bash
pg_dump -h 127.0.0.1 -p 5432 -U postgres -d mydb -Fd -j 4 -f "D:\backup\mydb_dir"
```

### 4.2 并行恢复

```bash
pg_restore -h 127.0.0.1 -p 5432 -U postgres -d mydb_restore -j 4 "D:\backup\mydb_dir"
```

### 4.3 custom 格式并行恢复

```bash
pg_restore -h 127.0.0.1 -p 5432 -U postgres -d mydb_restore -j 4 "D:\backup\mydb.dump"
```

**注意**

- 并行备份：主要用 `-Fd`
- 并行恢复：`custom` 和 `directory` 都支持

---

## 5. 按范围备份

### 5.1 只备份表结构

```bash
pg_dump -h 127.0.0.1 -p 5432 -U postgres -d mydb -s -f "D:\backup\schema.sql"
```

### 5.2 只备份数据

```bash
pg_dump -h 127.0.0.1 -p 5432 -U postgres -d mydb -a -f "D:\backup\data.sql"
```

### 5.3 只备份某张表

```bash
pg_dump -h 127.0.0.1 -p 5432 -U postgres -d mydb -t public.orders -Fc -f "D:\backup\orders.dump"
```

### 5.4 只备份某个 schema

```bash
pg_dump -h 127.0.0.1 -p 5432 -U postgres -d mydb -n public -Fc -f "D:\backup\public.dump"
```

### 5.5 排除某张表

```bash
pg_dump -h 127.0.0.1 -p 5432 -U postgres -d mydb --exclude-table=public.audit_log -Fc -f "D:\backup\mydb_no_audit.dump"
```

### 5.6 只排除某张表的数据，保留结构

```bash
pg_dump -h 127.0.0.1 -p 5432 -U postgres -d mydb --exclude-table-data=public.audit_log -Fc -f "D:\backup\mydb_no_audit_data.dump"
```

---

## 6. 按范围恢复

### 6.1 只恢复表结构

```bash
pg_restore -h 127.0.0.1 -p 5432 -U postgres -d mydb_restore -s "D:\backup\mydb.dump"
```

### 6.2 只恢复数据

```bash
pg_restore -h 127.0.0.1 -p 5432 -U postgres -d mydb_restore -a "D:\backup\mydb.dump"
```

### 6.3 只恢复某张表

```bash
pg_restore -h 127.0.0.1 -p 5432 -U postgres -d mydb_restore -t public.orders "D:\backup\mydb.dump"
```

### 6.4 只恢复某个 schema

```bash
pg_restore -h 127.0.0.1 -p 5432 -U postgres -d mydb_restore -n public "D:\backup\mydb.dump"
```

---

## 7. 备份整个实例

### 7.1 备份所有数据库 + 角色 + 表空间

```bash
pg_dumpall -h 127.0.0.1 -p 5432 -U postgres -f "D:\backup\cluster.sql"
```

### 7.2 恢复整个实例

```bash
psql -h 127.0.0.1 -p 5432 -U postgres -d postgres -f "D:\backup\cluster.sql"
```

**注意**

- `pg_dumpall` 只能输出 SQL
- 恢复时通常要用高权限用户

---

## 8. 只备份角色 / 表空间（globals）

```bash
pg_dumpall -h 127.0.0.1 -p 5432 -U postgres --globals-only -f "D:\backup\globals.sql"
```

恢复：

```bash
psql -h 127.0.0.1 -p 5432 -U postgres -d postgres -f "D:\backup\globals.sql"
```

**常见迁移顺序**

1. 先恢复 `globals.sql`
2. 再恢复各数据库 dump

---

## 9. 自动建库恢复

如果想让恢复时自动创建数据库：

```bash
pg_restore -h 127.0.0.1 -p 5432 -U postgres -C -d postgres "D:\backup\mydb.dump"
```

**说明**

- `-C` = create database
- 连接到一个已存在的库，一般用 `postgres`

---

## 10. 常用参数速查

| 参数 | 作用 |
|---|---|
| `-h` | 主机 |
| `-p` | 端口 |
| `-U` | 用户 |
| `-d` | 数据库 |
| `-f` | 输出文件 |
| `-Fc` | custom 格式 |
| `-Fd` | directory 格式 |
| `-Fp` | plain SQL 格式 |
| `-j 4` | 4 并行任务 |
| `-s` | schema only |
| `-a` | data only |
| `-t table` | 指定表 |
| `-n schema` | 指定 schema |
| `--clean` | 恢复前删除对象 |
| `--if-exists` | 配合 `--clean` 使用 |
| `-v` | verbose |
| `-W` | 强制提示输入密码 |
| `-O` / `--no-owner` | 不恢复对象 owner |
| `-x` / `--no-privileges` | 不恢复 GRANT/ACL |

---

## 11. 常见问题

### Q1. `pg_restore: input file appears to be a text format dump`

原因：你拿 `.sql` 给了 `pg_restore`。
做法：改用 `psql`。

---

### Q2. 恢复时报 `role "xxx" does not exist`

做法：

- 先恢复 `globals.sql`
- 或恢复时加：

```bash
pg_restore --no-owner --no-privileges -d mydb_restore "D:\backup\mydb.dump"
```

---

### Q3. 恢复到新环境经常权限/owner 出错

推荐：

```bash
pg_restore -h 127.0.0.1 -p 5432 -U postgres -d mydb_restore --no-owner --no-privileges "D:\backup\mydb.dump"
```

---

### Q4. 恢复慢

可尝试：

- 使用 `-j 4` 并行恢复
- 用 `custom` 或 `directory` 格式
- 恢复到空库
- 减少索引/约束冲突场景

---

## 12. 实战推荐套路

### 场景 A：日常单库备份

```bash
pg_dump -h 127.0.0.1 -p 5432 -U postgres -d mydb -Fc -f "D:\backup\mydb.dump"
```

### 场景 B：迁移到新环境

```bash
pg_dumpall -h 127.0.0.1 -p 5432 -U postgres --globals-only -f "D:\backup\globals.sql"
pg_dump -h 127.0.0.1 -p 5432 -U postgres -d mydb -Fc -f "D:\backup\mydb.dump"

psql -h 127.0.0.1 -p 5432 -U postgres -d postgres -f "D:\backup\globals.sql"
createdb -h 127.0.0.1 -p 5432 -U postgres mydb
pg_restore -h 127.0.0.1 -p 5432 -U postgres -d mydb --no-owner --no-privileges "D:\backup\mydb.dump"
```

### 场景 C：想只恢复一张表

```bash
pg_restore -h 127.0.0.1 -p 5432 -U postgres -d mydb_restore -t public.orders "D:\backup\mydb.dump"
```

---

## 13. 查看备份里有什么

```bash
pg_restore -l "D:\backup\mydb.dump"
```

这个命令很实用，能先看 dump 里包含哪些对象。

---

## 14. 进阶：物理备份（整库灾备）

如果你需要的是 **整实例级别灾备 / PITR**，常用的是 `pg_basebackup`：

```bash
pg_basebackup -h 127.0.0.1 -p 5432 -U replicator -D "D:\backup\base" -Fp -Xs -P
```

**适用**

- 整库灾备
- 主从搭建
- 时间点恢复（配合 WAL 归档）

**不适合**

- 只恢复某张表
- 灵活的数据迁移

---

## 15. 最后给你一个“最短版”

### 备份

```bash
pg_dump -h 127.0.0.1 -p 5432 -U postgres -d mydb -Fc -f "D:\backup\mydb.dump"
```

### 恢复

```bash
createdb -h 127.0.0.1 -p 5432 -U postgres mydb_restore
pg_restore -h 127.0.0.1 -p 5432 -U postgres -d mydb_restore "D:\backup\mydb.dump"
```

### 规则

- `.sql` → `psql`
- `.dump` → `pg_restore`

---
