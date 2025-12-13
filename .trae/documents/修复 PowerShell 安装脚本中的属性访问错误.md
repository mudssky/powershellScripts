## 问题分析
`install.ps1` 执行失败是因为 `profile_unix.ps1` 中的 `Set-AliasProfile` 函数访问了不存在的 `command` 属性。

## 根本原因
`profile_unix.ps1` 中存在两个 `$userAlias` 数组定义：
1. 脚本级别数组（第40-83行）：包含有 `command` 属性的对象
2. `Set-CustomAliasesProfile` 函数内数组（第285-305行）：没有 `command` 属性的对象

`Set-AliasProfile` 函数使用脚本级别的 `$userAlias`，但数组中对象结构不一致。

## 修复方案
1. **统一对象结构**: 为脚本级别 `$userAlias` 数组中缺少 `command` 属性的对象添加该属性，或设为 `$null`
2. **增强属性检查**: 在 `Set-AliasProfile` 函数中使用更安全的属性检查方式
3. **代码重构**: 将别名配置统一管理，避免重复定义

## 实施步骤
1. 修复脚本级别 `$userAlias` 数组中对象的结构一致性
2. 优化 `Set-AliasProfile` 函数中的属性检查逻辑
3. 测试修复后的脚本执行