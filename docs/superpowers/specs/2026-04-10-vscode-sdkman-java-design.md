# VS Code Terminal SDKMAN Java Auto-Switch Design

## Summary

本设计只解决一个明确目标：在 VS Code 集成终端中打开 Java 项目后，如果当前目录或后续 `cd` 到的目录包含 `.sdkmanrc`，则自动切换到该文件声明的 Java 版本。

本方案不修改普通终端行为，不尝试完整复刻 SDKMAN 的 auto-env 生命周期，也不处理离开项目目录后的自动恢复。

## Context

当前仓库中的 [`shell/shared.d/java.sh`](/home/administrator/projects/env/powershellScripts/shell/shared.d/java.sh) 负责初始化 SDKMAN。实际排查发现：

- SDKMAN 本机配置已经启用 `sdkman_auto_env=true`
- 在普通交互式 Bash 中，进入 `/home/administrator/projects/work/java/mdm-boot` 后，`java -version` 可以自动切换到 `.sdkmanrc` 中声明的 `8.0.482.fx-zulu`
- 在 VS Code 集成终端中，`sdkman_auto_env` 函数存在，但 `PROMPT_COMMAND` 被 VS Code 的 shell integration 改写为 `__vsc_prompt_cmd_original`
- 用户的真实目标不是修复全部 auto-env 机制，而是确保 VS Code 新开终端进入项目后，Java 版本就是 `.sdkmanrc` 中指定的版本

## Goals

- 仅在 VS Code 集成终端中生效
- 尽量少改动现有逻辑
- 避免引入轮询、延迟任务或额外性能开销
- 让“新开 VS Code 终端后进入项目目录”这一常见路径能正确切换 Java 版本

## Non-Goals

- 不修复所有 shell 环境下的 SDKMAN auto-env 行为
- 不处理 `pushd`、`popd` 或其他目录栈命令
- 不在离开项目目录后自动执行 `sdk env clear`
- 不改动 VS Code 配置、SDKMAN 全局配置或其他 shell 模块

## Constraints

- 修改范围限定在 [`shell/shared.d/java.sh`](/home/administrator/projects/env/powershellScripts/shell/shared.d/java.sh)
- 需要兼容当前机器上可能发生的重复 `source` 场景，避免重复包装 `cd`
- 只在 `sdk` 已完成初始化且当前 shell 为交互式时触发附加逻辑

## Chosen Approach

采用“仅 VS Code 环境包装 `cd`”的最小方案。

### Trigger Scope

- 通过 `TERM_PROGRAM=vscode` 判断当前是否为 VS Code 集成终端
- 非 VS Code 环境直接保持现状，不附加任何兼容逻辑

### Startup Behavior

- 在 `java.sh` 完成 SDKMAN 初始化后，如果当前 shell 是 VS Code 集成终端，并且当前目录存在 `.sdkmanrc`，执行一次 `sdk env`
- 这样可以覆盖“终端启动后初始目录已经是项目目录”的情况

### Directory Change Behavior

- 为 VS Code 环境包装 `cd`
- 新包装函数先调用原始 `cd`
- 仅当 `cd` 成功时才继续检查新目录
- 若新目录中存在 `.sdkmanrc`，执行 `sdk env`
- 若新目录中不存在 `.sdkmanrc`，则不执行任何额外动作

### Idempotency

- 包装前先检查是否已经完成包装，避免因为重复 `source` 造成多层嵌套
- 启动期的一次性同步也应避免重复触发

## Rationale

选择该方案的原因如下：

- 它直接命中用户真实诉求：只要 VS Code 终端进入项目目录时 Java 版本正确即可
- 它绕开了 VS Code 对 `PROMPT_COMMAND` 的包装影响，不再依赖提示符钩子链条
- 它比重新实现完整的 SDKMAN 环境清理逻辑更短、更稳定、更容易理解
- 它不会影响普通终端，也不会在每次提示符刷新时增加额外开销

## Trade-offs

- 当用户离开项目目录后，当前 shell 可能仍保持项目使用的 Java 版本
- 只有 `cd` 触发目录变更时才会补切换，`pushd`/`popd` 不在本次范围内
- 如果 VS Code 或其他工具以非 `cd` 方式修改当前目录，本方案不会额外兜底

这些取舍是有意为之，用来换取最小改动和最低复杂度。

## Verification Plan

以下验证以 `java -version` 为准，而不是 `sdk current java`：

1. 在 VS Code 中新开一个 Bash 终端，切到 `/home/administrator/projects/work/java/mdm-boot`，确认 `java -version` 显示 `1.8.0_482`
2. 在同一个 VS Code Bash 终端中，从其他目录执行 `cd /home/administrator/projects/work/java/mdm-boot`，确认 `java -version` 显示 `1.8.0_482`
3. 在普通非 VS Code 终端中确认 `cd` 行为不变，没有新增输出或异常副作用

## Deferred Work

如果后续需要更完整的体验，可以在后续独立变更中再考虑：

- 为 `pushd` / `popd` 增加一致行为
- 离开项目目录时恢复默认 Java 版本
- 针对 Zsh 和 Bash 的目录切换路径做统一抽象

本设计不包含这些扩展内容。
