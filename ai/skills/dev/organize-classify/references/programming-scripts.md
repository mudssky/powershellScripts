# 脚本型项目目录结构

## 先识别

- 脚本语言：Shell、PowerShell、Python、Node、Deno、Ruby 等。
- 是一次性脚本、可复用工具、安装器、运维 wrapper、还是可发布 CLI。
- 是否需要跨平台、测试、打包、bin shim 或生成单文件产物。

## 简单脚本集合

```text
scripts/
  filesystem/
  network/
  devops/
  media/
```

按主要使用场景分类，不要只按脚本里偶然调用的命令分类。

## 工具型脚本

```text
tool/
  main.ps1 | main.sh
  lib/
  tests/
  examples/
```

入口负责参数解析、帮助、确认和退出码；复杂逻辑放 `lib`、`core` 或语言惯用模块目录。

## 单文件分发

```text
tool/
  src/
  build/
  tests/
  dist/
    tool.sh
```

规则：

- 源码真相和生成产物分开。
- 生成产物如果提交，必须能追溯到构建脚本。
- 不手工修改生成产物修 bug。

## bin shim

`bin/` 适合放稳定可执行入口或 shim。shim 应指向源码入口，不应复制一份会漂移的逻辑，除非有明确构建流程。

## PowerShell 模块

PowerShell 可按模块组织：

```text
ModuleName/
  ModuleName.psd1
  ModuleName.psm1
  Public/
  Private/
  tests/
```

小模块也可以单 `.psm1`，但公共函数、私有 helper、测试和 manifest 边界要清楚。

## 避免

- 把所有脚本放进 `misc` 直到无法查找。
- 复制入口到多个目录形成多套真相。
- 批量移动脚本后忘记更新 PATH、bin shim、文档、CI 和定时任务。
- 把本机私有配置和 secret 放进可提交脚本目录。
