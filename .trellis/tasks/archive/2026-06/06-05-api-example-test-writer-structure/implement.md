# 完善 API 示例测试编写 skill 结构 - Implement

## Checklist

- [x] 更新 `SKILL.md`：
  - [x] 在工作流中加入“所有请求块补面向人的接口注释”。
  - [x] 扩展默认目录约定为渐进层级规则。
  - [x] 加入 CLI 与 VS Code 插件配置兼容原则。
  - [x] 加入长行处理原则。
  - [x] 添加新 reference 的读取路由。
- [x] 新增或更新 `references/`：
  - [x] 写接口注释模板、好/坏示例和覆盖范围。
  - [x] 写目录层级选择规则、小/中/大型项目参考树和放置规则。
  - [x] 写目录化 env/dotenv-first 的 CLI + httpYac VS Code 插件兼容配置样例。
  - [x] 简要补充 REST Client 兼容提示，不把它作为主目标。
  - [x] 写长参数、长 URL、长 header、长 JSON body 和长 CLI 命令的处理方式。
- [x] 更新 `examples/httpyac/auth-smoke.http`：
  - [x] 为登录、当前用户、手动登录请求补注释。
  - [x] 保留可运行 httpyac 元数据和断言。
- [x] 更新 `examples/httpyac/async-task.http`：
  - [x] 为初始化块、提交任务、轮询状态、读取结果补注释。
  - [x] 说明轮询、失败和超时断言意图。
- [x] 验证：
  - [x] 检查 Markdown 和 `.http` 中没有真实密钥、生产 token 或个人凭据。
  - [x] 检查每个示例请求块都有面向人的注释。
  - [x] 只改文档和 `.http` 示例时，不执行根目录 `pnpm qa`，最终说明原因。

## Validation Commands

```bash
rg -n "token|password|secret|Cookie|Authorization" ai/skills/dev/api-example-test-writer
rg -n "^###|# @name" ai/skills/dev/api-example-test-writer/examples/httpyac/*.http
rg -n "httpyac\\.environment|envDirName|REST Client|dotenv|--env|--var|--tag|换行|长行" ai/skills/dev/api-example-test-writer
git diff -- ai/skills/dev/api-example-test-writer .trellis/tasks/06-05-api-example-test-writer-structure
```

## Risky Files

- `ai/skills/dev/api-example-test-writer/SKILL.md`：入口太长会降低 skill 可用性，长模板应放 reference。
- `examples/httpyac/*.http`：注释不能破坏 httpyac 元数据、变量引用和断言语法。

## Before Start

- 用户已确认目录层级先不新增实际分层 `.http` 示例目录，优先在 reference 中提供目录树样例。
- 用户倾向 env/dotenv-first，避免默认维护两套业务变量。
- 用户已确认 env 文件采用目录化方案，主要面向 httpYac CLI 和 httpYac VS Code 插件。
