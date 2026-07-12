# LobeHub External Services Migration Design

## 背景

当前项目的主配置文件 [`docker-compose.yml`](/Volumes/Data/env/lobe-chat-db/docker-compose.yml) 同时编排了 LobeHub 应用和多类基础设施服务：

- ParadeDB/PostgreSQL
- Redis
- RustFS
- `rustfs-init`
- SearXNG

本次调整的目标不是改动应用功能，而是重划分部署职责：

- 宿主机统一运行并复用 ParadeDB、Redis、RustFS 容器
- 当前项目只保留 LobeHub 自身和项目级初始化任务
- 保留一套“内置依赖版”配置，便于回滚和独立运行

## 已确认约束

- 当前环境为 Docker Desktop，可使用 `host.docker.internal` 访问宿主机服务
- 宿主机上的 ParadeDB、Redis、RustFS 由用户后续自行部署，本次不负责部署
- 宿主机服务端口保持不变：
  - PostgreSQL/ParadeDB：`5432`
  - Redis：`6379`
  - RustFS API：`9000`
  - RustFS Console：`9001`
- 默认模式下，当前项目不再占用宿主机 `9000/9001`
- 主配置只做“外部基础设施模式”的配置调整
- `rustfs-init` 保留在当前项目中
- `searxng` 保留在当前项目中
- 需要保留一套完整的回滚配置：
  - `docker-compose.with-internal-db.yml`
  - `.env.with-internal-services`
- 本次需要额外提供一份使用文档

## 目标

### 主目标

- 让默认的 [`docker-compose.yml`](/Volumes/Data/env/lobe-chat-db/docker-compose.yml) 不再管理 ParadeDB、Redis、RustFS
- 让 LobeHub 和 `rustfs-init` 直接连接宿主机上的共享基础设施
- 让项目的默认启动语义变成“启动应用层”，而不是“启动整套基础设施”

### 次目标

- 降低多个项目重复持有同类数据库/缓存/对象存储容器的浪费
- 保留低成本回滚路径
- 让配置职责更清晰，便于后续维护

## 非目标

- 不负责宿主机 ParadeDB、Redis、RustFS 容器的创建与运行
- 不负责现有数据库、Redis、RustFS 数据迁移
- 不调整 LobeHub、SearXNG、RustFS 的功能行为
- 不重构现有启动脚本的整体使用方式

## 推荐方案

采用“应用层瘦身版”方案：

- 主 [`docker-compose.yml`](/Volumes/Data/env/lobe-chat-db/docker-compose.yml) 切换为外部基础设施模式
- 新增 [`docker-compose.with-internal-db.yml`](/Volumes/Data/env/lobe-chat-db/docker-compose.with-internal-db.yml) 作为内置依赖回滚版
- 主 [.env](/Volumes/Data/env/lobe-chat-db/.env) 切换为外部基础设施模式
- 新增 [`.env.with-internal-services`](/Volumes/Data/env/lobe-chat-db/.env.with-internal-services) 作为内置依赖回滚版

选择该方案的原因：

- 改动范围集中在配置层，符合“只改配置并补文档”的要求
- 默认行为与新的部署职责一致
- 回滚路径清晰，不需要重新拼凑旧配置
- 在 Docker Desktop 环境下，`host.docker.internal` 比固定设备名或局域网 IP 更稳妥

## 架构边界

### 迁移到宿主机复用的服务

- `postgresql`
- `redis`
- `rustfs`

### 保留在项目 compose 中的服务

- `network-service`
- `lobe`
- `searxng`
- `rustfs-init`

### 边界说明

- `rustfs` 是共享基础设施，应迁出当前项目
- `rustfs-init` 是 LobeHub 项目级初始化任务，应保留在当前项目
- `rustfs-init` 只负责确保 LobeHub 使用的 bucket 和策略存在，不负责管理共享 RustFS 的全局状态
- `searxng` 暂不迁出，因为宿主机没有复用需求
- `network-service` 本次先保留，用于维持 `lobe` 的网络承载和 `3210` 端口暴露，避免在同一次变更中叠加不必要的网络重构
- 由于 RustFS 已迁出当前项目，默认模式下 `network-service` 不能继续占用 `9000/9001`，否则会与宿主机 RustFS 端口冲突

## 配置设计

### 1. 主 compose

主 [`docker-compose.yml`](/Volumes/Data/env/lobe-chat-db/docker-compose.yml) 做如下调整：

- 删除服务块：
  - `postgresql`
  - `redis`
  - `rustfs`
- 调整 `network-service.ports`：
  - 保留 `${LOBE_PORT}:3210`
  - 删除 `${RUSTFS_PORT}:9000`
  - 删除 `9001:9001`
- 保留服务块：
  - `network-service`
  - `lobe`
  - `searxng`
  - `rustfs-init`
- 更新 `lobe.depends_on`：
  - 移除 `postgresql`
  - 移除 `redis`
  - 移除 `rustfs`
  - 保留 `network-service`
  - 保留 `rustfs-init`
  - 保留 `searxng`
- 更新 `lobe.environment`：
  - `DATABASE_URL=${DATABASE_URL}`
  - `REDIS_URL=${REDIS_URL}`
  - `S3_ENDPOINT=${S3_ENDPOINT}`
- 保留现有其它与 LobeHub 直接相关的环境变量
- 更新 `rustfs-init` 的目标地址：
  - 从 `http://network-service:9000`
  - 改为 `http://host.docker.internal:9000`
- 移除不再需要的宿主机别名配置：
  - 删除 `macmini:host-gateway`

### 2. 主 env

主 [.env](/Volumes/Data/env/lobe-chat-db/.env) 做如下调整：

- 明确外部基础设施连接：
  - `DATABASE_URL` 直接写完整连接串，主机为 `host.docker.internal:5432`，库名为 `lobechat`，密码使用宿主机 ParadeDB 的实际密码
  - `REDIS_URL=redis://host.docker.internal:6379`
  - `S3_ENDPOINT=http://host.docker.internal:9000`
  - `S3_PUBLIC_DOMAIN` 使用浏览器可直接访问的宿主机地址，例如 `http://macmini:9000`
- 保留项目自身仍需使用的变量：
  - `LOBE_PORT`
  - `APP_URL`
  - `KEY_VAULTS_SECRET`
  - `AUTH_SECRET`
  - `RUSTFS_ACCESS_KEY`
  - `RUSTFS_SECRET_KEY`
  - `RUSTFS_LOBE_BUCKET`
  - `JWKS_KEY`
  - 其他 LobeHub 自身需要的现有变量
- 从主 `.env` 中移除仅用于内置依赖模式的变量：
  - `LOBE_DB_NAME`
  - `POSTGRES_PASSWORD`
  - `RUSTFS_PORT`

这样处理的原因：

- 主 `.env` 的语义应明确为“外部基础设施连接”
- 回滚模式已经有独立的 [`.env.with-internal-services`](/Volumes/Data/env/lobe-chat-db/.env.with-internal-services)
- 避免主 `.env` 同时混入两种模式的变量，降低维护歧义
- RustFS 需要区分“容器内访问宿主机”的地址与“浏览器侧访问对象文件”的地址

### 3. 回滚配置

新增 [`docker-compose.with-internal-db.yml`](/Volumes/Data/env/lobe-chat-db/docker-compose.with-internal-db.yml)：

- 内容以本次调整前的主 [`docker-compose.yml`](/Volumes/Data/env/lobe-chat-db/docker-compose.yml) 为基础
- 保留内部 `postgresql`、`redis`、`rustfs`
- 作为“内置依赖版”回滚入口

新增 [`.env.with-internal-services`](/Volumes/Data/env/lobe-chat-db/.env.with-internal-services)：

- 内容以本次调整前的主 [.env](/Volumes/Data/env/lobe-chat-db/.env) 为基础
- 保持与内置依赖版 compose 配套
- 作为完整回滚环境文件

### 4. 启动脚本

[`start.sh`](/Volumes/Data/env/lobe-chat-db/start.sh) 可以继续保留原有命令入口。

本次仅需评估是否补充少量帮助文本，说明默认模式已经改为外部基础设施模式。若为减少改动范围，也可不改脚本，只在使用文档中明确说明默认模式的变化。

## 数据流与启动关系

默认模式下的依赖关系如下：

1. `network-service` 仅暴露 LobeHub 的 `3210` 端口
2. `searxng` 继续在项目内部网络中运行
3. `rustfs-init` 连接宿主机 RustFS，确保 `lobe` bucket 和对应策略存在
4. `lobe` 启动后连接：
   - 宿主机 ParadeDB
   - 宿主机 Redis
   - 宿主机 RustFS（容器侧通过 `S3_ENDPOINT` 访问）
   - 项目内 `searxng`

同时，浏览器或外部访问对象文件时使用 `S3_PUBLIC_DOMAIN` 对应的可访问地址，而不是 `host.docker.internal`。

这里显式接受一个前提：宿主机基础设施需先于项目应用层准备完成。本项目不再承担这些服务的生命周期管理。

## 错误处理与失败策略

### 外部服务未就绪

若宿主机上的 ParadeDB、Redis、RustFS 未启动或端口不可达：

- `lobe` 会因连接失败而无法正常提供服务
- `rustfs-init` 会因无法访问 RustFS 而失败

处理策略：

- 使用文档中明确要求先部署宿主机共享服务
- 在排障部分说明如何检查 `host.docker.internal` 连通性和端口占用

### bucket 初始化失败

若 `rustfs-init` 执行失败：

- `lobe` 依赖的 bucket 可能不存在
- 上传/对象存储功能可能异常

处理策略：

- 文档中明确 `rustfs-init` 的职责
- 文档中给出重新执行 `rustfs-init` 的命令

### 回滚失败风险

若只回滚 compose 而不回滚 `.env`，可能出现“配置文件版本不一致”的问题。

处理策略：

- 文档中明确主模式与回滚模式必须成对使用：
  - 主模式：`docker-compose.yml` + `.env`
  - 回滚模式：`docker-compose.with-internal-db.yml` + `.env.with-internal-services`

## 验证设计

由于本次不部署宿主机容器，验证目标限定为“配置正确且可解释”。

需要完成的验证包括：

- `docker compose config` 能正常展开默认模式配置
- `docker compose -f docker-compose.with-internal-db.yml --env-file .env.with-internal-services config` 能正常展开回滚模式配置
- 默认模式中不再引用已删除的内部服务名：
  - `postgresql`
  - `redis`
  - `rustfs`
- 默认模式中不再占用宿主机 `9000/9001`
- `rustfs-init` 已指向 `host.docker.internal:9000`
- 使用文档中的文件名、命令、端口号与实际配置一致

## 使用文档要求

新增文档至少覆盖以下内容：

- 默认模式说明：依赖宿主机已有 ParadeDB、Redis、RustFS
- 宿主机共享服务端口要求
- 默认模式下只有 LobeHub 由当前项目占用宿主机端口，RustFS 端口由宿主机服务自身占用
- 说明 `S3_ENDPOINT` 与 `S3_PUBLIC_DOMAIN` 的职责区别
- 默认模式启动命令
- 回滚模式启动命令
- `docker-compose.yml` 与 `docker-compose.with-internal-db.yml` 的职责区别
- `.env` 与 `.env.with-internal-services` 的职责区别
- 常见故障排查：
  - `host.docker.internal` 无法访问
  - PostgreSQL 连接失败
  - Redis 连接失败
  - RustFS/bucket 初始化失败

## 实施步骤

1. 复制当前主配置生成回滚文件：
   - [`docker-compose.with-internal-db.yml`](/Volumes/Data/env/lobe-chat-db/docker-compose.with-internal-db.yml)
   - [`.env.with-internal-services`](/Volumes/Data/env/lobe-chat-db/.env.with-internal-services)
2. 修改主 [`docker-compose.yml`](/Volumes/Data/env/lobe-chat-db/docker-compose.yml) 为外部基础设施模式
3. 修改主 [.env](/Volumes/Data/env/lobe-chat-db/.env) 为外部基础设施模式
4. 新增使用文档
5. 运行配置展开验证
6. 保留回滚命令示例并在文档中说明

## 风险与取舍

- 保留 `network-service` 会让配置中继续存在一层历史结构，但能显著降低本次改动风险
- 为避免宿主机 RustFS 端口冲突，默认模式必须移除主 compose 中的 `9000/9001` 端口暴露
- 不处理宿主机基础设施部署，意味着最终联调成功依赖后续宿主机容器部署质量

## 结论

本次设计的核心是把当前仓库从“应用 + 基础设施混合编排”调整为“应用层编排”，并通过一套显式的回滚文件保留旧模式。这样既能满足宿主机复用 ParadeDB、Redis、RustFS 的目标，也能把本次修改范围控制在配置和文档层面，符合当前需求。
