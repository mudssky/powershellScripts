# psutils 运行时加固设计

## Candidate Gate

每个静态分析候选先记录：触发条件、实际影响、是否用户显式行为、跨平台差异、现有测试和建议处理。结论只能是 Fix、Documented Exception 或 No Issue。

优先候选：

- `Set-SSHKeyAuth` 的 passphrase/native command 参数暴露与交互语义。
- `Invoke-FzfHistorySmart` 中用户选择历史命令后的动态执行边界。
- `env.psm1`、`hardware.psm1`、`network.psm1`、`proxy.psm1` 的空 catch 可诊断性。
- `$Host`、`$args`、`$matches` 等自动变量命名是否产生真实行为或仅为分析器误报。
- Windows、Linux、macOS 下路径、HOME/USERPROFILE 和外部命令缺失行为。

## Security Boundary

- 不在日志、error、verbose 或返回对象中输出 secret。
- 若 native tool 必须接收敏感参数，记录平台限制并优先使用交互输入、stdin 或临时受控通道。
- 历史命令执行必须由用户显式按键触发；若保留动态执行，帮助中说明它执行当前会话历史内容，不接收外部搜索结果。

## Error Handling

- 缓存读取失败等可降级异常写 `Verbose` 后继续。
- 资源检测、网络调用或配置写入的不可恢复异常返回结构化失败或抛出，不静默吞掉。
- 不把所有 `Write-Host` 改为对象输出；交互命令保留合理的 host UI。

## Tests

- 每个 Fix 都有聚焦 Pester 测试。
- 外部命令通过 module wrapper 或 mock 边界验证参数，不执行真实 SSH、代理、网络或系统修改。
- 跨平台差异通过纯输入/平台描述测试，真实 Windows 行为依赖 CI。

## Rollback

- 加固改变交互行为时保留兼容开关或回退到原行为并增加明确 warning。
- 静态分析器误报通过局部说明处理，不全局禁用规则。
