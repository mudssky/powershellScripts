# psutils 核心契约设计

## Canonical Entry

- `psutils/psutils.psd1` 是唯一规范入口，目录导入应解析到该 manifest。
- manifest 声明 `PowerShellVersion = '7.4'`、`CompatiblePSEditions = @('Core')`。
- `psutils/index.psm1` 只作为兼容 shim：输出弃用 warning，并在调用者可见作用域导入 `psutils.psd1`。
- 仓库生产脚本、tests、examples 和 docs 不再引用 shim。

实现时必须用子进程测试验证“导入 shim 返回后公共命令仍可见”，不能只检查 shim 内部导入成功。

## Export Contract

- 新增聚合模块契约测试，从 manifest 读取导出列表并与实际 `Get-Command -Module psutils` 对比。
- 测试拒绝重复导出名、不存在的函数和参数契约静默覆盖。
- `Test-ModuleFunction` 当前无实现、无消费者，按内部错误导出移除，不为兼容虚构新实现。
- `Read-ConfigEnvFile` 与 `Resolve-DefaultEnvFiles` 按 shared config resolver 规范从 `config.psm1` 和 manifest 导出。
- `New-Shortcut` 以 `win.psm1` 的完整实现为权威；旧 `Path`/`Destination` 参数通过参数 alias 兼容，删除 `functions.psm1` 的重复实现与重复导出。

## Consumer Migration

- `ai/downloadModels.ps1` 改为导入 manifest，并以 `-ListOnly` 做无下载 smoke test。
- `tree-examples.ps1` 改为规范入口。
- 缓存 demo 的错误相对路径由文档与示例子任务处理，避免本任务扩张。

## Tests

- 新增 manifest/entry 契约测试文件。
- 为 shim、目录导入、manifest 导入和关键命令参数集使用独立 `pwsh -NoProfile` 子进程，避免当前会话残留模块掩盖问题。
- 保留并扩展 config、functions、win 的聚焦测试。
- 直接导入 `install.psm1`、`test.psm1`、`hardware.psm1` 等跨模块消费者，验证直接依赖可见。

## Compatibility

- 不支持 Windows PowerShell 5.1；错误元数据改为真实约束不是破坏已成立契约。
- shim 是临时兼容入口，不在 README 中作为推荐方式。
- 不改变 shared config resolver 与 WSL Docker wrapper 的行为语义。

## Rollback

- shim 导入作用域不稳定时，保留 shim 文件并改用经测试的显式转发方案；不恢复空文件。
- 参数 alias 引发歧义时，恢复两个内部函数名但只导出一个公共 wrapper。
- 契约测试保留，即使具体兼容实现需要回退。
