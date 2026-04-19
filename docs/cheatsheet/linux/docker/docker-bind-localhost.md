# Docker 端口绑定 localhost 操作速查

## 适用场景

这份文档适合下面几类需求：

- 希望 Docker 容器服务只允许宿主机本地访问
- 想保留宿主机上的 `psql`、DBeaver、浏览器、本地脚本访问能力
- 不希望局域网或公网客户端直接连到容器端口
- 正在评估 `localhost` 绑定和防火墙拦截的差异

## 一句话结论

把 Docker 端口从：

```text
5432:5432
```

改成：

```text
127.0.0.1:5432:5432
```

含义是：

- 宿主机本机还能访问
- 外部机器不能直接访问
- 同一 Docker 网络内的其他容器通常仍可通过服务名互联
- 依赖 `host.docker.internal` 访问宿主机端口的容器，可能会受影响

## `docker run` 怎么写

### 绑定到 IPv4 localhost

```bash
docker run -d \
  --name postgre-dev \
  -p 127.0.0.1:5432:5432 \
  -e POSTGRES_PASSWORD=your-password \
  postgres:latest
```

说明：

- 左边的 `127.0.0.1:5432` 是宿主机监听地址和端口
- 右边的 `5432` 是容器内部端口
- 只有宿主机自己能访问 `127.0.0.1:5432`

### 同时绑定 IPv6 localhost

如果你明确需要 IPv6 回环地址，也可以额外处理，但大多数场景只绑定 `127.0.0.1` 就够了。

## Docker Compose 怎么写

### 常见写法

```yaml
services:
  postgre:
    image: postgres:latest
    ports:
      - "127.0.0.1:5432:5432"
```

### Web 服务示例

```yaml
services:
  gotify:
    image: gotify/server
    ports:
      - "127.0.0.1:30080:80"
```

### 对比写法

默认公网暴露写法：

```yaml
services:
  postgre:
    ports:
      - "5432:5432"
```

区别：

- `"5432:5432"` 通常会绑定到 `0.0.0.0` / `::`
- `"127.0.0.1:5432:5432"` 只绑定到本机回环地址

## 已有容器怎么改

Docker 端口映射不是热修改项，通常需要重建容器。

### 如果你使用 Docker Compose

1. 修改 `compose.yml` 或 `docker-compose.yml`
2. 重新创建容器

```bash
docker compose up -d --force-recreate postgre
```

如果服务名不是 `postgre`，把命令里的服务名换成实际名称。

### 如果你使用 `docker run`

通常做法是：

1. 记录原容器需要保留的挂载、环境变量、镜像参数
2. 停掉并删除旧容器
3. 用新的 `-p 127.0.0.1:宿主机端口:容器端口` 重新创建

示例：

```bash
docker stop postgre-dev
docker rm postgre-dev

docker run -d \
  --name postgre-dev \
  -p 127.0.0.1:5432:5432 \
  -e POSTGRES_PASSWORD=your-password \
  -v /data/postgresql:/var/lib/postgresql/data \
  postgres:latest
```

## 怎么验证是否真的只绑定了 localhost

### 看 Docker 端口映射

```bash
docker ps --format 'table {{.Names}}\t{{.Ports}}'
```

理想结果类似：

```text
postgre-dev    127.0.0.1:5432->5432/tcp
```

### 看容器端口绑定详情

```bash
docker inspect --format '{{json .HostConfig.PortBindings}}' postgre-dev
```

理想结果类似：

```json
{"5432/tcp":[{"HostIp":"127.0.0.1","HostPort":"5432"}]}
```

### 看宿主机监听地址

```bash
ss -ltnp | rg ':5432\b'
```

理想结果应显示监听在 `127.0.0.1:5432`，而不是 `0.0.0.0:5432`。

## 使用上会有什么区别

### 宿主机本地工具

通常没有区别。

例如下面这些仍然可用：

- `psql -h 127.0.0.1 -p 5432`
- DBeaver 连接 `127.0.0.1:5432`
- 浏览器打开 `http://127.0.0.1:30080`

### 外部机器

会失效。

例如：

- 局域网其他机器
- 公网客户端
- 其他通过服务器公网 IP 访问该端口的设备

它们不能再直接访问这个端口。

### 同一 Docker 网络内的其他容器

通常不受影响，但前提是它们走容器网络互联，而不是走宿主机端口。

例如：

```text
postgresql://postgres:password@postgre:5432/app
```

这种通过服务名 `postgre` 连接的方式，通常仍然可用。

### 依赖 `host.docker.internal` 的容器

这是最容易踩坑的点。

如果另一个容器是这样连数据库：

```text
postgresql://postgres:password@host.docker.internal:5432/app
```

那么把数据库改成只绑定 `127.0.0.1:5432:5432` 之后，这条路径往往会失效。

原因是：

- `host.docker.internal` 指向的是宿主机地址
- 容器访问宿主机时，不等价于访问宿主机自己的 `localhost`
- 服务只监听在 `127.0.0.1` 时，很多来自容器侧的连接到不了这个监听点

## 什么时候不适合直接绑 localhost

下面这些场景要先评估：

- 其他容器依赖 `host.docker.internal:端口`
- 需要从另一台电脑直接连接数据库或后台
- 需要把服务提供给局域网设备
- 需要通过服务器的 Tailscale IP 直接访问这个端口

如果命中了这些场景，常见替代方案是：

- 改成同一 Docker 网络内用服务名互联
- 绑定到内网 IP、Tailscale IP 或其他非公网地址
- 保持端口发布，但用防火墙限制来源

## 常见替代方案

### 方案 1：同网络服务名访问

最推荐用于“应用容器访问数据库容器”的场景。

```yaml
services:
  app:
    environment:
      DATABASE_URL: postgresql://postgres:password@postgre:5432/app

  postgre:
    image: postgres:latest
```

特点：

- 不依赖宿主机端口
- 容器之间直接通过 Docker 网络通信
- 更适合长期维护

#### 场景 A：应用和数据库在同一个 Compose 文件里

这是最简单的做法。Docker Compose 会为同一个项目自动创建默认网络，服务会自动加入这个网络，并且可以直接用服务名互相访问。

注意：

- 同一个 Compose 文件内，通常不需要额外写 `networks`
- 只有你明确需要自定义网络边界、别名或跨项目共享网络时，才需要显式增加 `networks` 配置

示例：

```yaml
services:
  app:
    image: your-app
    environment:
      DATABASE_URL: postgresql://postgres:password@postgre:5432/app
    depends_on:
      - postgre

  postgre:
    image: postgres:latest
    environment:
      POSTGRES_PASSWORD: password
      POSTGRES_DB: app
```

操作步骤：

1. 确认应用服务和数据库服务位于同一个 `docker-compose.yml`
2. 把连接串里的主机名改成数据库服务名，例如 `postgre`
3. 如果数据库只给其他容器用，可以去掉 `ports`
4. 重建服务

```bash
docker compose up -d --force-recreate app postgre
```

如果你还想让宿主机本地工具访问数据库，可以保留：

```yaml
services:
  postgre:
    ports:
      - "127.0.0.1:5432:5432"
```

这时会同时满足两件事：

- 容器内应用走 `postgre:5432`
- 宿主机工具走 `127.0.0.1:5432`

#### 场景 B：应用和数据库不在同一个 Compose 文件里

这种情况下，需要手动创建一个共享 Docker 网络，然后让两边都加入这个网络。

先创建共享网络：

```bash
docker network create app-net
```

数据库所在的 Compose：

```yaml
services:
  postgre:
    image: postgres:latest
    environment:
      POSTGRES_PASSWORD: password
      POSTGRES_DB: app
    networks:
      - app-net

networks:
  app-net:
    external: true
```

应用所在的 Compose：

```yaml
services:
  app:
    image: your-app
    environment:
      DATABASE_URL: postgresql://postgres:password@postgre:5432/app
    networks:
      - app-net

networks:
  app-net:
    external: true
```

操作步骤：

1. 创建共享网络，例如 `app-net`
2. 在数据库和应用两个 Compose 中都引用这个外部网络
3. 保持连接串主机名为数据库服务名 `postgre`
4. 分别重建两个 Compose 项目

#### 怎么验证服务名访问已经生效

先确认两个容器在同一个网络里：

```bash
docker inspect <container-name> --format '{{json .NetworkSettings.Networks}}'
```

再进入应用容器确认服务名能解析：

```bash
docker exec -it <app-container> sh
getent hosts postgre
```

如果镜像里没有 `getent`，也可以尝试：

```bash
ping -c 1 postgre
```

最后确认端口可达：

```bash
nc -zv postgre 5432
```

#### 常见注意事项

- 服务名只在同一个 Docker 网络内有效，宿主机自己不能直接用 `postgre:5432`
- `depends_on` 只保证启动顺序，不保证数据库已经准备好接受连接
- 如果容器使用了 `network_mode: host`，通常不适合这种服务发现方式
- 如果同一个网络里存在重名服务，排查时要确认容器实际加入的是哪个网络
- 显式增加共享 `networks` 会提高配置复杂度，并可能让多个 Compose 项目之间的网络边界变得更模糊

### 方案 2：继续对外发布，但用防火墙拦公网

适合：

- 现有容器已经依赖 `host.docker.internal`
- 暂时不想改连接串
- 只想先降低公网暴露风险

特点：

- 兼容现有用法更好
- 但安全层级不如直接绑 `localhost`

### 方案 3：走 SSH 隧道或 Tailscale

适合：

- 数据库或后台只给自己访问
- 远程访问需求稳定但不希望公开端口

## 参考排查命令

查看所有对外发布端口：

```bash
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
```

查看某个容器的端口绑定：

```bash
docker inspect --format '{{json .HostConfig.PortBindings}}' <container>
```

查看宿主机当前监听地址：

```bash
ss -ltnp
```

查看是否还有容器在使用 `host.docker.internal`：

```bash
rg -n "host\\.docker\\.internal" -S .
```

## 推荐实践

- 数据库、对象存储控制台、管理后台优先考虑只绑定 `localhost`
- 容器之间优先使用服务名互联，不长期依赖 `host.docker.internal`
- 防火墙作为第二层兜底，不作为唯一安全边界
- 改完后同时用 `docker ps`、`docker inspect`、`ss -ltnp` 三种方式核对结果

## 相关阅读

- [容器端口暴露与防护速查](../server/container-port-exposure-hardening.md)
