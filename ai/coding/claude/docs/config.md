我来帮您查找 Claude Code CLI 的配置文件相关信息。

基于我获取的 Claude Code CLI 文档，我来为您详细解答配置文件的几种方式和项目开发中的配置方法。

## Claude Code CLI 配置文件的几种方式

### 1. **环境变量配置**

这是最基础的配置方式，通过设置环境变量来控制 Claude Code 的行为：

```bash
# API 密钥配置
export ANTHROPIC_API_KEY=sk-ant-...
export OPENAI_API_KEY=sk-...

# 模型配置
export ANTHROPIC_DEFAULT_SONNET_MODEL=claude-sonnet-4-5

# 行为控制
export CLAUDE_BASH_NO_LOGIN=1  # 跳过登录 shell
export NO_PROXY=localhost,127.0.0.1  # 绕过代理
export CLAUDE_CODE_EXIT_AFTER_STOP_DELAY=5000  # 5秒空闲后自动退出
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1  # 禁用非必要网络流量
export DISABLE_AUTOUPDATER=1  # 禁用包管理器更新通知
```

### 2. **JSON 设置文件配置 (`settings.json`)**

这是最核心和灵活的配置方式，支持多个层级：

#### 项目级配置 (`.claude/settings.json`)

```json
{
  "permissions": {
    "allow": [
      "Bash(npm run lint)",
      "Bash(npm run test:*)",
      "Read(**/*.{js,ts,json,md})"
    ],
    "deny": [
      "Read(./.env)",
      "Read(./secrets/**)",
      "Bash(rm -rf:*)"
    ]
  },
  "env": {
    "NODE_ENV": "development",
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1"
  },
  "model": "claude-sonnet-4-5",
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true
  }
}
```

#### 用户级配置 (`~/.claude/settings.json`)

```json
{
  "permissions": {
    "permissionMode": "acceptEdits"
  },
  "spinnerTipsEnabled": true,
  "statusLine": {
    "enabled": true,
    "format": "{{model}} | {{tokens}}"
  }
}
```

### 3. **内存文件配置 (`CLAUDE.md`)**

这是项目级别的指导性配置文件：

```markdown
# 项目指导原则

## 代码风格
- 使用 TypeScript 严格模式
- 遵循 ESLint 规则
- 组件使用 PascalCase 命名

## 测试要求
- 所有功能必须有单元测试
- 测试覆盖率不低于 80%
- 使用 Jest 作为测试框架

## 部署流程
1. 运行测试套件
2. 构建项目
3. 部署到 staging 环境
4. 运行集成测试
5. 部署到生产环境
```

### 4. **MCP 服务器配置**

扩展 Claude Code 功能的配置：

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@anthropic-ai/mcp-server-github"],
      "oauth": {
        "clientId": "your-client-id",
        "clientSecret": "your-client-secret",
        "scopes": ["repo", "issues"]
      }
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/files"]
    }
  }
}
```

### 5. **钩子系统配置**

在工具执行前后运行自定义命令：

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python3 /path/to/validator.py"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit",
        "hooks": [
          {
            "type": "command",
            "command": "npm run lint"
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "type": "command",
        "command": "echo 'Session started'"
      }
    ]
  }
}
```

## 平常项目开发的最佳配置实践

### 1. **基础项目配置结构**

```
your-project/
├── .claude/
│   ├── settings.json      # 项目级配置
│   └── CLAUDE.md         # 项目指导文件
├── package.json
└── tsconfig.json
```

### 2. **推荐的 settings.json 配置**

```json
{
  "permissions": {
    "allow": [
      "Read(**/*.{js,ts,tsx,jsx,json,md,yml,yaml})",
      "Edit(**/*.{js,ts,tsx,jsx})",
      "Bash(npm:*)",
      "Bash(git:*)",
      "Bash(node:*)",
      "Bash(npx:*)"
    ],
    "deny": [
      "Read(./.env*)",
      "Read(./dist/**)",
      "Read(./node_modules/**)",
      "Bash(rm -rf:*)",
      "Bash(sudo:*)"
    ],
    "ask": [
      "Bash(git push:*)",
      "Bash(npm publish:*)",
      "Edit(./package.json)"
    ]
  },
  "env": {
    "NODE_ENV": "development",
    "CLAUDE_CODE_ENABLE_TELEMETRY": "0"
  },
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true
  },
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "npm run check-deps"
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit(**/*.{js,ts})",
        "hooks": [
          {
            "type": "command",
            "command": "npm run lint -- --fix"
          }
        ]
      }
    ]
  }
}
```

### 3. **项目 CLAUDE.md 示例**

```markdown
# 项目：React TypeScript 应用

## 技术栈
- React 18+ with TypeScript
- Vite as build tool
- Tailwind CSS for styling
- React Query for data fetching

## 代码规范
- 使用 TypeScript 严格模式
- 组件文件使用 PascalCase
- 工具函数使用 camelCase
- 常量使用 UPPER_SNAKE_CASE

## 开发流程
1. 创建功能分支
2. 编写代码和测试
3. 运行 `npm run test` 和 `npm run lint`
4. 提交代码（使用约定式提交）
5. 创建 PR

## 常用命令
- `npm run dev` - 启动开发服务器
- `npm run build` - 构建生产版本
- `npm run test` - 运行测试
- `npm run lint` - 代码检查
- `npm run type-check` - TypeScript 类型检查

## 项目结构
src/
├── components/    # React 组件
├── hooks/         # 自定义 hooks
├── utils/         # 工具函数
├── types/         # TypeScript 类型定义
├── services/      # API 服务
└── pages/         # 页面组件
```

### 4. **团队协作配置**

对于团队项目，建议：

1. **项目级配置** (`git clone` 后自动生效)
   - `.claude/settings.json` 提交到版本控制
   - `CLAUDE.md` 包含团队开发规范

2. **用户级配置** (个人偏好，不提交到版本控制)
   - `~/.claude/settings.json` 包含个人 API 密钥等

3. **环境变量配置** (在 CI/CD 中使用)

   ```bash
   # .env.example (提交到版本控制)
   ANTHROPIC_API_KEY=your_api_key_here
 
   # .env.local (不提交到版本控制)
   ANTHROPIC_API_KEY=sk-ant-actual_key
   ```

### 5. **配置优先级**

Claude Code 的配置优先级为：

1. **Enterprise 级别配置** (企业策略)
2. **用户级配置** (`~/.claude/`)
3. **项目级配置** (`./.claude/`)
4. **环境变量**
5. **命令行参数**

这种配置系统允许在不同层级进行细粒度的控制，既保证了团队的一致性，又支持个性化定制。
