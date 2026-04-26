# Bash 脚本开发规范

本文档总结 `scripts/bash/` 下现有脚本的组织方式、编码约定、构建策略与测试要求。新 Bash 工具优先遵循这里的约定，除非目标脚本有明确的兼容性限制。

## 适用范围

- 单文件 Bash 工具，例如 `scripts/bash/aliyun-oss-put.sh`。
- 目录型 Bash 工具，例如 `scripts/bash/systemd-service-manager/`。
- 根级 Bash 构建入口，例如 `scripts/bash/build.sh`。
- Bash 工具相关的模板、夹具、文档与 Vitest 测试。

## 目录组织

简单工具优先使用单文件：

```text
scripts/bash/<tool-name>.sh
scripts/bash/<tool-name>.env.example
```

当脚本开始出现多个命令、多个解析器、模板、渲染逻辑或较多测试夹具时，应升级为目录型工具：

```text
scripts/bash/<tool-name>/
  main.sh
  common.sh
  build.sh
  commands/
  lib/
  templates/
  tests/
  README.md
  vitest.config.ts
```

目录型工具的边界建议如下：

- `main.sh`：只做模块加载、公共参数解析后的命令分发。
- `common.sh`：放共享日志、错误出口、运行时初始化等基础能力。
- `commands/`：每个用户可见命令一个文件，例如 `install.sh`、`list.sh`。
- `lib/`：放可复用的解析、校验、渲染、系统调用封装。
- `templates/`：放初始化或构建时需要内嵌的模板。
- `tests/`：放 Vitest 测试与测试夹具。

## 单文件工具规范

单文件工具适合职责清晰、依赖少、命令面窄的脚本。参考 `aliyun-oss-put.sh`：

- 文件名使用小写短横线，保留 `.sh` 后缀，例如 `aliyun-oss-put.sh`。
- 开头声明用途、输入来源、配置优先级与退出码。
- 默认启用严格模式：

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
```

- 依赖检查要前置，缺失依赖应给出明确退出码与错误信息。
- CLI 参数、环境变量、`.env` 文件的优先级必须在帮助和 README 中保持一致。
- 不直接 `source` 用户可编辑配置文件；需要读取 `.env` 时使用受控 parser。
- 默认输出保持安静，调试信息通过 `--verbose` 或 `--debug-*` 显式开启。

## 大脚本拆分与构建策略

当工具需要拆成多个 Bash 文件时，采用“开发态拆分、发布态单文件”的策略。参考 `systemd-service-manager`。

开发态入口：

- `main.sh` 通过 `source` 加载 `common.sh`、`lib/`、`commands/`。
- 每个模块用 `SSM_*_LOADED` 这类 guard 防止重复加载。
- 模块顺序必须稳定，先加载基础能力，再加载 parser/render/systemd 封装，最后加载 commands 与 `main.sh`。

发布态构建：

- 工具自己的 `build.sh` 负责生成单文件产物。
- 构建脚本显式维护 `MODULES=(...)` 顺序，缺文件时立即失败。
- 构建产物应写到根目录 `bin/<tool-name>`。
- 如需便携副本，可同时写到工具目录，例如 `systemd-service-manager.local.sh`。
- 单文件产物开头写入 `SSM_STANDALONE=1`，避免运行时再次按开发态加载模块。
- 模板通过 here-doc 内嵌到构建产物，不依赖安装目标机器仍保留源码目录。
- 构建产物是生成文件，不应手工编辑；改源码模块后重新运行构建。

根级统一构建：

- `scripts/bash/build.sh` 管理所有 Bash 工具的 `bin` 产物。
- 目录型工具使用 `build` 目标，调用子目录自己的 `build.sh`。
- 单文件 `.sh` 工具使用 `copy` 目标，复制到 `bin/<name>` 并去掉 `.sh` 后缀。
- 新增 Bash 工具时，需要把目标加入 `BASH_BUILD_TARGETS`，并补充 `--list`、`--only`、失败摘要相关测试。

## 函数与注释

所有 Bash 函数必须有中文注释，说明核心功能、参数与返回值。注释解释设计意图和非直观逻辑，不复述基础语法。

推荐格式：

```bash
# 解析构建入口参数，并写入 BB_* 全局状态。
# 参数：构建入口收到的原始命令行参数。
# 返回值：解析成功返回 0；参数非法时直接退出。
bb_parse_args() {
  ...
}
```

复杂逻辑应补充设计意图，例如：

- 为什么不用 `source` 加载用户配置。
- 为什么构建时要固定模块顺序。
- 为什么发布态要设置 standalone 标记。
- 为什么某段 shell quoting 需要特殊处理。

## 编码风格

- 优先使用 `#!/usr/bin/env bash`。
- 默认使用 `set -Eeuo pipefail`；若脚本需要兼容更老环境，可退到 `set -euo pipefail` 并在文件头说明原因。
- 所有变量展开默认加双引号：`"${value}"`。
- 局部变量使用 `local`。
- 数组用于固定清单、命令参数和 pathspec，避免把列表塞进字符串。
- 命名按脚本前缀隔离：
  - 根级 Bash build 使用 `bb_*` / `BB_*`。
  - systemd-service-manager 使用 `ssm_*` / `SSM_*`。
- 错误统一走 `die` / `ssm_die` / `bb_die` 一类 helper。
- 日志统一带工具前缀，方便 CI 和用户定位来源。
- 文件复制和安装优先使用 `install -m` 或 `cp + chmod`，并显式设置可执行权限。
- 尽量避免 `eval`。必须使用时，命令来源、引用方式和测试覆盖要写清楚。

## 配置与安全

- 不执行用户配置文件，只解析受控 `KEY=VALUE`。
- 配置 key 必须校验字符集，例如 `^[A-Za-z_][A-Za-z0-9_]*$`。
- 逻辑名称、unit 前缀、目标名等会进入文件名或命令参数的值必须校验安全字符集。
- `.env.local` 用于本机私有覆盖，不应作为默认共享配置。
- 示例配置使用 `.env.example` 或 `*.conf.example`，不要放真实密钥。
- 需要输出签名、token 或敏感请求内容时，必须默认脱敏，并只在显式 debug 模式下输出。

## CLI 设计

- 每个脚本都应提供 `--help` 或 `help`。
- 帮助文本至少包含用途、必填参数、可选参数、环境变量和示例。
- 公共参数在入口层统一解析，命令参数在命令模块内部解析。
- 未知参数必须失败，不允许静默忽略。
- dry-run、list、status 这类命令应适合自动化读取；必要时提供 `--json`。
- 输出摘要保持稳定，例如 `key=value` 或固定字段顺序，方便测试和脚本调用。

## 测试规范

Bash 工具优先用 Vitest 驱动真实 shell 脚本：

- 测试通过 `execa('bash', [...])` 调用脚本，而不是只测 helper。
- 每个测试创建临时 workspace，避免污染仓库根目录。
- 对外部命令使用临时 `mock-bin` 放假命令，并通过 `PATH` 注入。
- 需要验证生成文件时，断言文件存在、内容关键行和可执行位。
- 目录型工具要覆盖源码入口和构建产物入口。
- 构建脚本至少覆盖：
  - `--list` 元数据。
  - 单文件 copy 目标。
  - 目录型 build 目标。
  - 失败摘要与非零退出码。

新增或修改 Bash 行为后运行：

```bash
pnpm run qa:bash
pnpm run qa:systemd-service-manager
```

如果改动影响 `install.ps1` 或 PowerShell 集成，也要运行对应 Pester 测试。纯文档改动不需要执行 QA。

## 文档要求

- `scripts/bash/README.md` 记录根级能力、构建入口和工具索引。
- 每个目录型工具保留自己的 `README.md`，记录命令、配置、构建、测试和质量门。
- 模板目录下的 `README.md` 说明生成出来的项目配置该怎么改。
- 新增 CLI 参数时同步更新脚本 help、README 和测试断言。
- 新增配置字段时同步更新 `*.example`、README 和 parser 测试。

## 新增 Bash 工具检查清单

- [ ] 选择单文件或目录型结构。
- [ ] 文件头说明用途、输入来源、退出码或关键行为。
- [ ] 所有函数都有中文参数和返回值说明。
- [ ] 不 `source` 用户配置文件，使用受控 parser。
- [ ] 帮助文本、README 和示例保持一致。
- [ ] 加入 `scripts/bash/build.sh` 的 `BASH_BUILD_TARGETS`。
- [ ] 单文件工具确认会复制到 `bin/<name>`，目录型工具确认自己的 `build.sh` 生成 `bin/<name>`。
- [ ] 新增或更新 Vitest 测试，覆盖正常路径和至少一个失败路径。
- [ ] 根据改动范围运行对应 QA；纯文档改动只需检查 Markdown 内容。
