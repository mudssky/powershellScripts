## ADDED Requirements

### Requirement: PowerShell 7+ 运行时基线
`profile.ps1` SHALL 仅支持 PowerShell 7+（`pwsh`）运行时，不提供 PowerShell 5.x 兼容路径。

#### Scenario: 受支持运行时正常加载
- **WHEN** 用户在 PowerShell 7+ 环境执行 `profile.ps1`
- **THEN** 系统 SHALL 继续执行统一入口初始化流程

#### Scenario: 非受支持运行时不受支持
- **WHEN** 用户在 Windows PowerShell 5.1 执行 `profile.ps1`
- **THEN** 系统 SHALL 不保证行为正确且不提供兼容分支

### Requirement: 用户别名配置目录化
用户别名配置 SHALL 从专用配置目录加载，而非直接放置在 `profile/` 根目录。

#### Scenario: 从配置目录加载用户别名
- **WHEN** profile 初始化扩展加载链路
- **THEN** 系统 SHALL 从约定的别名配置目录读取用户别名定义并完成注册

#### Scenario: 根目录不再承载别名配置文件
- **WHEN** 用户查看 `profile/` 根目录结构
- **THEN** 系统 SHALL 不再要求 `user_aliases.ps1` 位于根目录才能完成加载

## MODIFIED Requirements

### Requirement: 模块加载顺序可控
拆分后的实现 SHALL 采用确定性的 dot-source 顺序加载核心模块、配置加载器与功能模块，以避免函数未定义和作用域初始化错误。

#### Scenario: 核心模块先于功能模块
- **WHEN** profile 启动并开始加载内部脚本
- **THEN** 系统 SHALL 先加载模式决策与基础工具模块，再加载依赖这些能力的功能模块

#### Scenario: 配置加载器在功能执行前完成
- **WHEN** profile 进入扩展加载阶段
- **THEN** 系统 SHALL 在别名注册和帮助信息展示前完成配置脚本加载

## REMOVED Requirements

### Requirement: PowerShell 5.1 兼容性
**Reason**: 项目运行时基线已统一到 PowerShell 7+，继续维护 5.1 兼容分支会增加复杂度并降低演进效率。

**Migration**: 不提供迁移指导或兼容过渡，本次直接下线 5.1 兼容性要求。

#### Scenario: 旧兼容分支下线
- **WHEN** 系统完成本次变更并发布
- **THEN** 5.1 兼容分支 SHALL 从规范中移除，运行时行为以 PowerShell 7+ 为准
