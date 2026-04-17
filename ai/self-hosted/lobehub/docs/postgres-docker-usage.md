# PostgreSQL / ParadeDB 容器连接与查询说明

这份说明针对当前这台本地开发机上的 PostgreSQL / ParadeDB 容器。

当前活跃实例：

- 容器名：`dev-paradedb-paradedb-1`
- 对外端口：`5432`
- 当前数据库用户：`postgres`
- 当前密码：`12345678`

## 为什么 `docker exec ... psql` 不用密码

关键点不是 Docker 自动帮你登录了，而是这台 PostgreSQL 实例当前的认证规则允许“容器内本地连接”免密码。

当前容器里的 `pg_hba.conf` 实际规则是：

```conf
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
local   replication     all                                     trust
host    replication     all             127.0.0.1/32            trust
host    replication     all             ::1/128                 trust
host    all             all             all                     scram-sha-256
```

这表示：

- 在数据库容器内部，通过本地 Unix Socket 连接：免密码
- 在数据库容器内部，通过 `127.0.0.1` 连接：免密码
- 从宿主机、其他容器、局域网地址连接：需要密码

所以这条命令能直接执行：

```bash
docker exec dev-paradedb-paradedb-1 psql -U postgres -d postgres -c "ALTER ROLE postgres WITH PASSWORD '12345678';"
```

原因是：

1. `docker exec` 是在数据库容器内部启动 `psql`
2. 这条命令没有指定 `-h`
3. `psql` 默认走本地连接
4. 本地连接在 `pg_hba.conf` 里是 `trust`

## 为什么改了密码之后，`docker exec` 还是不用输密码

因为密码只对“需要密码的连接方式”生效。

比如下面这些场景会用到密码：

- LobeChat 通过 `DATABASE_URL` 从另一个容器连 `5432`
- 你在宿主机上用本地 `psql -h 127.0.0.1 -p 5432 ...` 去连
- 其他服务通过 TCP 去连这台数据库

但容器内部的本地 `trust` 连接不会校验密码，所以你即使把密码改成了 `12345678`，下面这种命令还是不会提示输入密码：

```bash
docker exec dev-paradedb-paradedb-1 psql -U postgres -d postgres -c "SELECT now();"
```

## 什么时候会要求输入密码

下面这种是典型“需要密码”的连接：

```bash
PGPASSWORD=12345678 psql -h 127.0.0.1 -p 5432 -U postgres -d lobechat
```

或者在容器里显式走外部地址：

```bash
docker exec dev-paradedb-paradedb-1 sh -lc "PGPASSWORD=12345678 psql -h host.docker.internal -p 5432 -U postgres -d lobechat"
```

如果你以后把 `pg_hba.conf` 的 `local` / `127.0.0.1` 规则改成 `scram-sha-256`，那容器内执行 `psql` 也会开始要求密码。

## 最方便的进入方式

### 方式 1：直接执行单条 SQL

适合临时查一条数据或者改配置。

```bash
docker exec dev-paradedb-paradedb-1 psql -U postgres -d lobechat -c "SELECT now();"
```

### 方式 2：进入交互式 `psql`

这是平时最推荐的方式。

```bash
docker exec -it dev-paradedb-paradedb-1 psql -U postgres -d lobechat
```

进入后常用命令：

- `\l`：列出数据库
- `\c lobechat`：切换数据库
- `\dn`：列出 schema
- `\dt`：列出当前 schema 下的表
- `\dt *.*`：列出所有 schema 的表
- `\d 表名`：看表结构
- `\x auto`：宽表结果自动纵向展示
- `\timing on`：显示 SQL 执行耗时
- `\q`：退出

### 方式 3：先进入容器，再手动执行

适合要连续跑很多命令，或者想顺便看容器内文件。

```bash
docker exec -it dev-paradedb-paradedb-1 bash
```

如果容器里没有 `bash`，就用：

```bash
docker exec -it dev-paradedb-paradedb-1 sh
```

进去后再执行：

```bash
psql -U postgres -d lobechat
```

## 常用查询命令

### 看有哪些数据库

```bash
docker exec dev-paradedb-paradedb-1 psql -U postgres -d postgres -c "\l"
```

### 看 `lobechat` 里有哪些表

```bash
docker exec dev-paradedb-paradedb-1 psql -U postgres -d lobechat -c "\dt"
```

如果想看所有 schema：

```bash
docker exec dev-paradedb-paradedb-1 psql -U postgres -d lobechat -c "\dt *.*"
```

### 看某张表的结构

把 `your_table` 换成真实表名。

```bash
docker exec dev-paradedb-paradedb-1 psql -U postgres -d lobechat -c "\d your_table"
```

### 查前 20 条数据

```bash
docker exec dev-paradedb-paradedb-1 psql -U postgres -d lobechat -c "SELECT * FROM your_table LIMIT 20;"
```

### 用扩展模式看一条记录

```bash
docker exec dev-paradedb-paradedb-1 psql -U postgres -d lobechat -c "\x on" -c "SELECT * FROM your_table LIMIT 1;"
```

## 容器名字怎么确认

如果以后容器名变化了，先查当前监听 `5432` 的是谁：

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
```

当前你这台机器上，真正对外提供 PostgreSQL 的是：

```text
dev-paradedb-paradedb-1
```

## 当前项目里有两套数据库模式

这个仓库里要区分两种模式：

- 默认外部数据库模式：LobeChat 连接宿主机 / 共享 ParadeDB
- 内置数据库模式：`docker-compose.with-internal-db.yml` 里会启动 `lobe-postgres`

你现在实际在用的是第一种，所以平时应该连：

```bash
docker exec -it dev-paradedb-paradedb-1 psql -U postgres -d lobechat
```

不是 `lobe-postgres`。

## 快速排查

### 1. LobeChat 启动时报数据库密码错误

先确认 `.env` 里的 `DATABASE_URL` 密码是不是和数据库里一致。

当前项目实际生效的是：

- [.env](../.env)

### 2. 我在容器里能连，应用却连不上

这通常不是密码没改成功，而是“连接来源”不同：

- 容器内本地连接：可能是 `trust`
- 应用容器到数据库容器：通常走 TCP，需要密码

所以判断密码是否可用，最好测一次 TCP 连接：

```bash
docker exec dev-paradedb-paradedb-1 sh -lc "PGPASSWORD=12345678 psql -h 127.0.0.1 -U postgres -d lobechat -Atc 'SELECT current_user, current_database();'"
```

### 3. 想确认当前实例的认证规则

```bash
docker exec dev-paradedb-paradedb-1 sh -lc "grep -v '^#' /var/lib/postgresql/data/pg_hba.conf | sed '/^$/d'"
```

## 推荐的日常用法

我更推荐下面这两条，基本覆盖 90% 的本地排查：

交互式进入数据库：

```bash
docker exec -it dev-paradedb-paradedb-1 psql -U postgres -d lobechat
```

快速执行单条查询：

```bash
docker exec dev-paradedb-paradedb-1 psql -U postgres -d lobechat -c "SELECT * FROM your_table LIMIT 20;"
```
