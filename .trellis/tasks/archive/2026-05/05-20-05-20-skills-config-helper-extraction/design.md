# design: config helper extraction

## Scope

本任务只扩展 `psutils` 的 config 公共 API，并把 skills 安装器切换到公共 API。公共 API 只处理通用配置对象访问，不处理路径、环境变量、平台选择或安装计划。

## Public API

复用既有 `ConvertTo-ConfigHashtable`，补强其输入兼容性：

* `$null` -> 空 hashtable
* `hashtable` -> 浅拷贝
* `System.Collections.IDictionary` -> 遍历 keys 转成普通 hashtable
* 其他对象 -> 遍历 `PSObject.Properties`

新增 `Get-ConfigValue`：

* 入参：`Values`、`Name`、`DefaultValue`
* `Values` 类型：`hashtable`
* key 匹配：`OrdinalIgnoreCase`
* 返回：命中值或默认值，命中时不改变 value 类型

## Data Flow

`Install-Skills.ps1` 已导入 `psutils/modules/process.psm1`。本任务保留现有 `Import-SkillsConfigModule`，让它导入 `psutils/modules/config.psm1`，并在脚本初始化阶段或首次读取配置前确保公共 helper 可用。

替换点：

* `ConvertTo-SkillsHashtable` -> `ConvertTo-ConfigHashtable`
* `Get-SkillsConfigValue` -> `Get-ConfigValue`

## Compatibility

`Install-Skills.ps1` 当前本地 helper 支持 `System.Collections.IDictionary`；`psutils` 现有 `ConvertTo-ConfigHashtable` 只处理 hashtable 和普通对象。因此需要先补强公共 helper，再替换调用方。

`Get-ConfigValue` 的行为应与现有 skills helper 一致：仅 shallow lookup，不做 nested path，不做 key normalization，不修改 key 大小写。

## Rollback

若 downstream 行为异常，可恢复 `Install-Skills.ps1` 本地 helper，保留 `psutils` 新 helper；新 API 为向后兼容新增，不影响现有调用方。
