
`pino` 是一个非常快速、低开销的 Node.js 日志库，它默认输出 JSON 格式的日志，非常适合在生产环境中进行结构化日志记录和分析。

---

## Pino 速查表 (Cheatsheet)

### 1. 安装

首先，你需要安装 `pino`:

```bash
npm install pino
```

### 2. 基本用法

开箱即用的 `pino` 非常简单。

```javascript
// index.js
import pino from 'pino'

const logger = pino()

// 记录不同级别的日志
logger.info('这是一条普通信息')
logger.warn('这是一条警告信息')
logger.error(new Error('这是一个错误'), '出错了！')

// 记录包含对象的信息
logger.info({ user: 'Alex', id: 123 }, '用户已登录')
```

**输出 (JSON 格式):**
默认情况下，`pino` 会将日志以 JSON 格式输出到标准输出 (stdout)。

```json
{"level":30,"time":1678886400000,"pid":12345,"hostname":"my-machine","msg":"这是一条普通信息"}
{"level":40,"time":1678886400001,"pid":12345,"hostname":"my-machine","msg":"这是一条警告信息"}
{"level":50,"time":1678886400002,"pid":12345,"hostname":"my-machine","err":{"type":"Error","message":"这是一个错误","stack":"..."},"msg":"出错了！"}
{"level":30,"time":1678886400003,"pid":12345,"hostname":"my-machine","user":"Alex","id":123,"msg":"用户已登录"}
```

### 3. 子记录器 (Child Loggers)

当你需要为一组日志添加固定的上下文信息时（例如，一个特定的请求 ID 或模块名），子记录器非常有用。

```javascript
import pino from 'pino'

const logger = pino()

// 创建一个子记录器，并绑定一个请求ID
const childLogger = logger.child({ requestId: 'req-abc-123' })

childLogger.info('开始处理请求...')
childLogger.warn('处理过程中发现一个问题。')
childLogger.info('请求处理完成。')
```

**输出:**
`requestId` 字段会自动出现在所有由 `childLogger` 生成的日志中。

```json
{"level":30,"time":1678886400004,"pid":12345,"hostname":"my-machine","requestId":"req-abc-123","msg":"开始处理请求..."}
{"level":40,"time":1678886400005,"pid":12345,"hostname":"my-machine","requestId":"req-abc-123","msg":"处理过程中发现一个问题。"}
{"level":30,"time":1678886400006,"pid":12345,"hostname":"my-machine","requestId":"req-abc-123","msg":"请求处理完成。"}
```

### 4. 日志美化 (开发环境)

在开发环境中，JSON 日志的可读性较差。我们可以使用 `pino-pretty` 来美化输出。

**首先，安装 `pino-pretty`:**

```bash
npm install pino-pretty --save-dev
```

**然后，在代码中配置 transport:**

```javascript
import pino from 'pino'

const logger = pino({
  transport: {
    target: 'pino-pretty',
    options: {
      colorize: true, // 添加颜色
      translateTime: 'SYS:yyyy-mm-dd HH:MM:ss', // 时间格式化
      ignore: 'pid,hostname' // 忽略某些字段
    }
  }
})

logger.info('美化后的日志输出')
logger.error(new Error('这是一个错误'), '美化后的错误')
```

**美化后的输出:**

```
[2023-03-15 12:00:00] INFO: 美化后的日志输出
[2023-03-15 12:00:00] ERROR: 美化后的错误
    Error: 这是一个错误
        at Object.<anonymous> (/path/to/your/script.js:15:14)
        ...
```

### 5. Transports (日志传输)

Transport 用于将日志发送到不同的目的地，例如文件、数据库或第三方日志服务。

#### a. 记录到文件

使用内置的 `pino/file` transport 将日志写入文件。

```javascript
import pino from 'pino'

const transport = pino.transport({
  target: 'pino/file',
  options: { 
    destination: './app.log', // 指定日志文件路径
    mkdir: true // 如果目录不存在，则自动创建
  }
})

const logger = pino(transport)
logger.info('这条日志将被写入文件。')
```

#### b. 多路传输 (Multiple Transports)

你可以同时将日志发送到多个地方，并为每个目的地设置不同的日志级别。

```javascript
import pino from 'pino'

const transport = pino.transport({
  targets: [
    {
      level: 'info', // info 及以上级别
      target: 'pino-pretty', // 在控制台美化输出
      options: {}
    },
    {
      level: 'error', // error 及以上级别
      target: 'pino/file', // 写入错误日志文件
      options: { destination: './app-error.log', mkdir: true }
    }
  ]
})

const logger = pino(transport)

logger.info('这条信息会出现在控制台。')
logger.warn('这条警告也会出现在控制台。')
logger.error('这条错误会同时出现在控制台和 app-error.log 文件中！')
```

#### c. 发送到第三方服务 (如 Sentry)

Pino 有丰富的生态，可以轻松集成各种日志服务。

**安装 Sentry transport:**
`npm install pino-sentry-transport`

**配置 Logger:**

```javascript
import pino from 'pino'

const transport = pino.transport({
  target: 'pino-sentry-transport',
  options: {
    sentry: {
      dsn: 'https://******@sentry.io/12345' // 你的 Sentry DSN
    },
    minLevel: 40, // 只发送 level >= 40 (warn) 的日志
  }
})

const logger = pino(transport)
logger.error(new Error('database connection failed'), '数据库连接失败，已上报Sentry')
```

### 6. 确保日志在程序退出前被发送

由于 Pino 的 transport 是异步的，如果你的脚本在日志写入完成前就退出了，可能会导致日志丢失。可以通过监听 `ready` 事件来确保日志被处理。

```javascript
import pino from 'pino'

const transport = pino.transport({
  target: 'pino/file',
  options: { destination: './app.log' }
})

const logger = pino(transport)

logger.info('这条日志很重要，不能丢失！')

// 在退出前确保 transport 已准备就绪并处理完日志
transport.on('ready', () => {
  // 如果需要，可以在这里安全地退出程序
  // process.exit(0)
})
```
