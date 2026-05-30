# 数据库客户端安装参考

## 使用原则

`database-query doctor` 用于检查底层客户端是否存在，并输出当前缺失工具的快速安装提示。安装命令只作为建议，agent 不应自动安装数据库客户端，除非用户明确要求。

安装后重新运行：

```bash
node scripts/database-query.js doctor
```

## PostgreSQL: psql

`psql` 来自 PostgreSQL client 工具。

```powershell
winget install PostgreSQL.PostgreSQL
scoop install postgresql
```

```bash
brew install libpq
sudo apt-get install postgresql-client
```

macOS 使用 `brew install libpq` 后，必要时把 `libpq/bin` 加入 `PATH`。

## MySQL: mysql

`mysql` 来自 MySQL client 或 MariaDB client。

```powershell
winget install Oracle.MySQL
scoop install mysql
```

```bash
brew install mysql-client
sudo apt-get install mysql-client
```

如果团队使用 MariaDB，也可安装 `mariadb-client`，但连接参数兼容性需要按实际版本确认。

## SQLite: sqlite3

```powershell
winget install SQLite.SQLite
scoop install sqlite
```

```bash
brew install sqlite
sudo apt-get install sqlite3
```

SQLite 只读场景优先透传 `--readonly`。

## MongoDB: mongosh

`mongosh` 是 MongoDB Shell。

```powershell
winget install MongoDB.Shell
scoop install mongosh
```

```bash
brew install mongosh
```

Debian/Ubuntu 建议按 MongoDB 官方仓库安装 `mongodb-mongosh`，不要混用过旧发行版包。

## Redis: redis-cli

`redis-cli` 通常随 Redis tools 安装。

```powershell
scoop install redis
```

```bash
brew install redis
sudo apt-get install redis-tools
```

Windows 上如果本机包不可用，优先在 WSL 或项目容器中安装 `redis-tools` 后运行。

## Milvus: Node SDK

Milvus 首版使用官方 Node.js SDK，作为可选外部运行依赖，不打包进 `scripts/database-query.js`。

```bash
pnpm add @zilliz/milvus2-sdk-node
npm install @zilliz/milvus2-sdk-node
```

安装位置必须是运行 `node scripts/database-query.js` 时 Node.js 能解析到的项目或 skill 目录。安装后用 `doctor` 确认 SDK 状态。

## 安全提示

- 不要为了安装方便把真实数据库密码写入 shell history。
- Windows/macOS/Linux 的包名可能随发行版变化，安装失败时优先查对应工具官方文档。
- 安装客户端不代表允许连接生产库；仍需按 `context` 输出确认实例、环境、库名和只读状态。
