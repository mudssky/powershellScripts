# Bash Scripts

这里存放以 `bash` 为运行时的轻量单文件脚本。

## Build

```bash
scripts/bash/build.sh
scripts/bash/build.sh --jobs 2
scripts/bash/build.sh --list
scripts/bash/build.sh --only aliyun-oss-put
```

`scripts/bash/build.sh` 统一刷新 Bash 工具的 `bin` 产物。目录型工具通过自己的 `build.sh` 生成产物；单文件 `.sh` 会复制到 `bin/<name>`，默认去掉 `.sh` 扩展。

## Docs

- [Bash 脚本开发规范](./docs/development-guidelines.md)

## aliyun-oss-put.sh

使用阿里云 OSS `PutObject` 接口上传单个本地文件。

### 适用场景

- 运行环境以 `Linux / macOS` 为主
- 只想上传单个文件
- 希望尽量只依赖系统常见工具
- 不想先安装 Python SDK 或 `ossutil`

### 依赖

- `bash`
- `curl`
- `openssl`

### 参数

```bash
./scripts/bash/aliyun-oss-put.sh \
  --file ./demo.txt \
  --bucket examplebucket \
  --key demo/demo.txt \
  --region cn-hangzhou \
  --host examplebucket.oss-cn-hangzhou.aliyuncs.com
```

可选参数：

- `--content-type`
- `--overwrite`
- `--verbose`
- `--debug-signing`

### 上传后的文件名

远端对象名由 `--key` 指定，`--key` 就是上传到 OSS 后看到的完整对象路径。

- 只改文件名：`--key renamed-demo.txt`
- 带目录一起指定：`--key release/2026-03-18/demo.txt`

例如本地文件叫 `./demo.txt`，也可以上传成另一个名字：

```bash
./scripts/bash/aliyun-oss-put.sh \
  --file ./demo.txt \
  --bucket examplebucket \
  --key archive/demo-renamed.txt \
  --region cn-hangzhou \
  --host examplebucket.oss-cn-hangzhou.aliyuncs.com
```

### 环境变量

脚本支持以下环境变量：

- `ALIYUN_ACCESS_KEY_ID`
- `ALIYUN_ACCESS_KEY_SECRET`
- `ALIYUN_SECURITY_TOKEN`
- `ALIYUN_OSS_BUCKET`
- `ALIYUN_OSS_OBJECT_KEY`
- `ALIYUN_OSS_REGION`
- `ALIYUN_OSS_HOST`
- `ALIYUN_OSS_CONTENT_TYPE`

### env 文件命名规范

为避免 `scripts/bash/` 下多个脚本共享通用 `.env` 时互相覆盖，env 文件名统一带脚本名：

- 共享默认值：`<script-name>.env`
- 本地私有覆盖：`<script-name>.env.local`
- 示例模板：`<script-name>.env.example`

以 `aliyun-oss-put.sh` 为例，对应文件名是：

- `aliyun-oss-put.env`
- `aliyun-oss-put.env.local`
- `aliyun-oss-put.env.example`

### aliyun-oss-put.env / aliyun-oss-put.env.local

脚本会在**当前工作目录**下自动读取：

1. `aliyun-oss-put.env`
2. `aliyun-oss-put.env.local`

优先级规则如下：

1. 当前 shell 已存在的环境变量
2. `aliyun-oss-put.env.local`
3. `aliyun-oss-put.env`

也就是说：

- `aliyun-oss-put.env` 先加载，`aliyun-oss-put.env.local` 后加载，因此后者优先级更高
- 但 `aliyun-oss-put.env` / `aliyun-oss-put.env.local` 都不会覆盖你已经 `export` 到当前 shell 的值

示例：

```dotenv
# aliyun-oss-put.env
ALIYUN_ACCESS_KEY_ID=your-access-key-id
ALIYUN_ACCESS_KEY_SECRET=your-access-key-secret
ALIYUN_OSS_BUCKET=examplebucket
ALIYUN_OSS_OBJECT_KEY=demo/demo.txt
ALIYUN_OSS_REGION=cn-hangzhou
ALIYUN_OSS_HOST=examplebucket.oss-cn-hangzhou.aliyuncs.com
```

```dotenv
# aliyun-oss-put.env.local
ALIYUN_SECURITY_TOKEN=your-sts-token
```

然后执行：

```bash
./scripts/bash/aliyun-oss-put.sh \
  --file ./demo.txt
```

如果你在命令行里显式传了 `--key`，它的优先级仍然高于 `ALIYUN_OSS_OBJECT_KEY`。

脚本会在发起上传前打印本地文件的 `sha256`、文件大小和目标 `object-key`，方便排查“传错文件”“内容被修改”这类问题。

### Host 说明

`--host` / `ALIYUN_OSS_HOST` 表示**实际发请求的 host**。

常见取值有两类：

- 标准 bucket 域名：`examplebucket.oss-cn-hangzhou.aliyuncs.com`
- 已绑定 bucket 的自定义域名：`static.example.com`

如果你传的是标准公共 endpoint，例如 `oss-cn-hangzhou.aliyuncs.com`，脚本会自动补成 `examplebucket.oss-cn-hangzhou.aliyuncs.com`。

> 注意：根据阿里云 OSS 官方文档，自 `2025-03-20` 起，中国内地新 OSS 用户对默认公共域名的数据 API 访问存在限制，很多场景需要改用自定义域名。

### 默认防覆盖

脚本默认发送 `x-oss-forbid-overwrite: true`，避免误覆盖同名对象。

如果你确实要替换已存在对象，显式传入：

```bash
./scripts/bash/aliyun-oss-put.sh \
  --file ./demo.txt \
  --bucket examplebucket \
  --key demo/demo.txt \
  --region cn-hangzhou \
  --host examplebucket.oss-cn-hangzhou.aliyuncs.com \
  --overwrite
```

### 当前边界

第一版刻意不支持：

- 目录上传
- 批量上传
- multipart upload
- 断点续传
- 并发上传
- Windows 原生执行体验

如果需求升级到这些范围，建议直接改用 Python 或官方 SDK，而不是继续把 Bash 逻辑堆厚。

## systemd-service-manager

用于按项目目录管理 systemd `service` / `timer`，适合“像 pm2 一样做基础管理，但最终运行时仍由 systemd 承担”的场景。

### 当前能力

- `init` 生成 `deploy/systemd/` 项目骨架
- `install` 渲染并安装 service / timer unit
- `start`、`stop`、`restart`、`status`、`logs`
- `enable`、`disable`
- 默认 `system` scope，也支持 `user` scope

### 测试

```bash
pnpm run test:systemd-service-manager
```
