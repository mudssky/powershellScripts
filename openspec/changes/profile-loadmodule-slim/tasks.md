## 1. 核心模块列表精简

- [ ] 1.1 修改 `core/loadModule.ps1`：将 `$coreModules` 改为平台条件化列表（Windows: 去掉 test+env，Linux/macOS: 去掉 test）
- [ ] 1.2 修改 `Debug-ProfilePerformance.ps1` Phase 3：同步核心模块加载逻辑与 loadModule.ps1 一致

## 2. 代理缓存 TTL 延长

- [ ] 2.1 修改 `features/environment.ps1`：`Invoke-WithCache` 的 `-MaxAge` 从 `[TimeSpan]::FromMinutes(5)` 改为 `[TimeSpan]::FromMinutes(30)`
- [ ] 2.2 修改 `Debug-ProfilePerformance.ps1` Phase 4 proxy-detect：同步缓存 TTL 为 30 分钟

## 3. Pester 防护栏更新

- [ ] 3.1 更新 `tests/DeferredLoading.Tests.ps1`：核心模块集合从 6 个改为 4 个（`os`、`cache`、`proxy`、`wrapper`），移除 `test` 和 `env` 的函数从同步路径白名单

## 4. 文档与验证

- [ ] 4.1 更新 `profile/README.md`：核心模块列表说明 + 性能基线数据
- [ ] 4.2 运行 `pnpm qa` 验证全部测试通过
