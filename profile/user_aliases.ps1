$projectRoot = Split-Path -Parent $PSScriptRoot

$userAlias = @(
    [PSCustomObject]@{
        cliName     = 'dust'
        aliasName   = 'du'
        aliasValue  = 'dust'
        description = 'dust 是一个用于清理磁盘空间的命令行工具。它可以扫描指定目录并显示占用空间较大的文件和目录，以便用户确定是否删除它们。'
    }
    [PSCustomObject]@{
        cliName     = 'duf'
        aliasName   = 'df'
        aliasValue  = 'duf'
        description = 'duf 是一个现代化的磁盘使用查看工具（df 的增强版），用于快速查看各分区的使用情况。'
    }
    [PSCustomObject]@{
        cliName     = 'zoxide'
        aliasName   = 'zq'
        aliasValue  = ''
        description = 'zoxide query 用于查询zoxide的数据库，显示最近访问的目录。'
        command     = 'zoxide'
        commandArgs = @('query')
    }
    [PSCustomObject]@{
        cliName     = 'zoxide'
        aliasName   = 'za'
        aliasValue  = ''
        description = 'zoxide add 用于将当前目录添加到zoxide的数据库中，以便下次快速访问。'
        command     = 'zoxide'
        commandArgs = @('add')
    }
    [PSCustomObject]@{
        cliName     = 'zoxide'
        aliasName   = 'zr'
        aliasValue  = 'zoxide'
        description = '如果你不希望某个目录再出现在 zoxide 的候选项中'
        command     = 'zoxide'
        commandArgs = @('remove')
    }
    [PSCustomObject]@{
        cliName     = 'eza'
        aliasName   = 'll'
        aliasValue  = ''
        description = 'll 使用 eza 显示详细文件列表（含图标、Git 状态、ISO 时间格式）。'
        command     = 'eza'
        commandArgs = @('--long', '--header', '--icons', '--git', '--all', '--time-style=iso')
    }
    [PSCustomObject]@{
        cliName     = 'eza'
        aliasName   = 'tree'
        aliasValue  = ''
        description = 'tree 使用 eza 显示目录树结构（含图标）。'
        command     = 'eza'
        commandArgs = @('--tree', '--git', '--icons', '--git-ignore')
    }
    [PSCustomObject]@{
        cliName     = 'claude'
        aliasName   = 'ccm'
        aliasValue  = ''
        description = 'ccm (Claude M) 启动 Claude 并加载 m 插件（任务管理）。'
        command     = 'claude'
        commandArgs = @('--plugin-dir', "$projectRoot\.claude\m")
    }
)
return $userAlias
