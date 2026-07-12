# Node.js PM2 使用 Cheatsheet

## 安装 PM2

```bash
# 使用 npm 安装
npm install pm2 -g

# 使用 bun 安装
bun install pm2 -g

# 安装开发版本
npm install git://github.com/Unitech/pm2.git#development -g
```

## 基本命令

### 启动应用

```bash
# 启动单个应用
pm2 start app.js

# 指定应用名称
pm2 start app.js --name "my-api"

# 传递参数给应用
pm2 start app.js -- -a 23

# 传递参数给 Node.js
pm2 start app.js --node-args="--debug=7001"

# 启动并指定日志文件
pm2 start app.js -e err.log -o out.log

# 启动并添加时间戳到日志
pm2 start app.js --log-date-format "YYYY-MM-DD HH:mm Z"

# 启动不同语言的应用
pm2 start echo.pl --interpreter=perl
pm2 start echo.py
pm2 start echo.php
pm2 start echo.sh
pm2 start echo.rb
pm2 start echo.coffee
```

### 集群模式

```bash
# 启动最大进程数（基于CPU核心数）
pm2 start app.js -i 0

# 启动指定数量的进程
pm2 start app.js -i 4

# 启动最大进程数-1
pm2 start app.js -i -1
```

### 监控模式

```bash
# 启用文件监控，文件变化时自动重启
pm2 start app.js --watch

# 忽略某些文件或目录的监控
pm2 start app.js --watch --ignore-watch="node_modules"
```

## 应用管理

### 查看应用状态

```bash
# 列出所有应用
pm2 list
pm2 ls

# 查看应用详细信息
pm2 describe <app-name|id>

# 查看应用日志
pm2 logs <app-name|id>

# 实时监控
pm2 monit
```

### 停止、重启、删除应用

```bash
# 停止应用
pm2 stop <app-name|id>
pm2 stop all  # 停止所有应用

# 重启应用
pm2 restart <app-name|id>
pm2 restart all  # 重启所有应用

# 重新加载应用（零停机时间）
pm2 reload <app-name|id>
pm2 reload all  # 重新加载所有应用

# 删除应用
pm2 delete <app-name|id>
pm2 delete all  # 删除所有应用
```

## 配置文件

### JSON 配置文件

```json
{
  "apps": [{
    "name": "my-app",
    "script": "app.js",
    "instances": 4,
    "exec_mode": "cluster",
    "watch": true,
    "max_memory_restart": "1G",
    "env": {
      "NODE_ENV": "development"
    },
    "env_production": {
      "NODE_ENV": "production"
    },
    "error_file": "./logs/err.log",
    "out_file": "./logs/out.log",
    "log_file": "./logs/combined.log",
    "time": true
  }]
}
```

### 使用配置文件

```bash
# 启动配置文件中的所有应用
pm2 start ecosystem.config.js

# 启动配置文件中的特定应用
pm2 start ecosystem.config.js --only worker-app

# 使用特定环境变量
pm2 start ecosystem.config.js --env production
```

## 环境管理

```bash
# 切换到生产环境
pm2 start app.json --env production

# 切换到开发环境
pm2 restart app.json --env development
```

## 日志管理

```bash
# 查看所有日志
pm2 logs

# 查看特定应用日志
pm2 logs <app-name|id>

# 清空所有日志
pm2 flush

# 清空特定应用日志
pm2 flush <app-name|id>

# 日志轮转设置
pm2 install pm2-logrotate
```

## 开机自启

```bash
# 生成启动脚本
pm2 startup

# 保存当前进程列表
pm2 save

# 禁用开机自启
pm2 unstartup
```

## 部署

### 生态系统配置文件示例

```javascript
module.exports = {
  apps: [{
    name: 'API',
    script: 'app.js',
    env: {
      COMMON_VARIABLE: 'true'
    },
    env_production: {
      NODE_ENV: 'production'
    }
  }],
  deploy: {
    production: {
      user: 'node',
      host: ['212.83.163.1', '212.83.163.2'],
      ref: 'origin/master',
      repo: 'git@github.com:repo.git',
      path: '/var/www/production',
      'post-deploy': 'npm install && pm2 reload ecosystem.config.js --env production',
      env: {
        NODE_ENV: 'production'
      }
    }
  }
};
```

### 部署命令

```bash
# 部署到生产环境
pm2 deploy ecosystem.config.js production

# 部署到开发环境
pm2 deploy ecosystem.config.js development
```

## 高级功能

### 内存限制和重启

```bash
# 当内存超过1GB时重启
pm2 start app.js --max-memory-restart 1G
```

### 定时重启

```bash
# 每天凌晨1点重启
pm2 start app.js --cron "0 1 * * *"
```

### 模块管理

```bash
# 安装模块
pm2 install <module-name>

# 查看已安装模块
pm2 list

# 卸载模块
pm2 uninstall <module-name>
```

### 多实例管理

```bash
# 使用不同的PM2_HOME运行多个PM2实例
PM2_HOME='.pm2' pm2 start app.js --name="app1"
PM2_HOME='.pm3' pm2 start app.js --name="app2"

# 查看不同实例
PM2_HOME='.pm2' pm2 list
PM2_HOME='.pm3' pm2 list
```

## 常用配置参数

| 参数 | 类型 | 示例 | 描述 |
|------|------|------|------|
| name | string | "myAPI" | 应用名称 |
| script | string | "app.js" | 脚本路径 |
| instances | number | 4 | 实例数量 |
| exec_mode | string | "cluster" | 执行模式 (fork/cluster) |
| watch | boolean | true | 监控文件变化 |
| max_memory_restart | string | "1G" | 内存限制 |
| env | object | {"NODE_ENV": "dev"} | 环境变量 |
| error_file | string | "./logs/err.log" | 错误日志文件 |
| out_file | string | "./logs/out.log" | 输出日志文件 |
| log_date_format | string | "YYYY-MM-DD HH:mm Z" | 日志时间格式 |
| merge_logs | boolean | true | 合并日志 |

## 常见问题解决

### 查看详细信息

```bash
# 查看PM2详细信息
pm2 show <app-name|id>

# 查看PM2版本
pm2 --version

# 查看帮助
pm2 --help
```

### 重置PM2

```bash
# 杀死PM2进程
pm2 kill

# 重启PM2守护进程
pm2 resurrect
```
