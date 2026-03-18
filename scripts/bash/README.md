# Bash Scripts

这里存放以 `bash` 为运行时的轻量单文件脚本。

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

### 环境变量

脚本支持以下环境变量：

- `ALIYUN_ACCESS_KEY_ID`
- `ALIYUN_ACCESS_KEY_SECRET`
- `ALIYUN_SECURITY_TOKEN`
- `ALIYUN_OSS_BUCKET`
- `ALIYUN_OSS_REGION`
- `ALIYUN_OSS_HOST`
- `ALIYUN_OSS_CONTENT_TYPE`

### .env / .env.local

脚本会在**当前工作目录**下自动读取：

1. `.env`
2. `.env.local`

优先级规则如下：

1. 当前 shell 已存在的环境变量
2. `.env.local`
3. `.env`

也就是说：

- `.env.local` 可以覆盖 `.env`
- 但 `.env` / `.env.local` 都不会覆盖你已经 `export` 到当前 shell 的值

示例：

```dotenv
# .env
ALIYUN_ACCESS_KEY_ID=your-access-key-id
ALIYUN_ACCESS_KEY_SECRET=your-access-key-secret
ALIYUN_OSS_BUCKET=examplebucket
ALIYUN_OSS_REGION=cn-hangzhou
ALIYUN_OSS_HOST=examplebucket.oss-cn-hangzhou.aliyuncs.com
```

```dotenv
# .env.local
ALIYUN_SECURITY_TOKEN=your-sts-token
```

然后执行：

```bash
./scripts/bash/aliyun-oss-put.sh \
  --file ./demo.txt \
  --key demo/demo.txt
```

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
