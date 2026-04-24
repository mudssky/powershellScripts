[CmdletBinding()]
param(
    # 默认执行 up，对齐“直接运行脚本即可启动”的现有使用习惯。
    [string]$Action = 'up',

    # 透传少量 compose 原生命令参数，避免为日志条数等小需求再扩脚本分支。
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ExtraArgs = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$composeFile = Join-Path $scriptDir 'compose.yaml'
$envFile = Join-Path $scriptDir '.env.local'

function Show-Usage {
    <#
    .SYNOPSIS
    输出 LiteLLM compose 包装脚本的用法说明。
    .OUTPUTS
    System.String
    返回完整用法文本，便于测试与调用方按需展示。
    #>
    $usage = @'
用法:
  ./start.ps1 [up|down|restart|logs|ps|pull|sync-models] [额外 compose 参数]

默认行为:
  ./start.ps1         -> docker compose up -d
  ./start.ps1 logs    -> docker compose logs -f litellm
  ./start.ps1 sync-models -> 用 litellm.local.yaml 同步数据库模型列表

示例:
  ./start.ps1
  ./start.ps1 restart
  ./start.ps1 sync-models
  ./start.ps1 logs --tail 100
  ./start.ps1 pull
'@

    Write-Host $usage
    return $usage
}

function Assert-DockerComposeReady {
    <#
    .SYNOPSIS
    检查 docker 与 docker compose 是否可用，并确认 compose 模板文件存在。
    #>
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        throw '未找到 docker 命令，请先安装并确认 Docker Desktop / Docker Engine 已加入 PATH。'
    }

    & docker 'compose' 'version' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw '未检测到可用的 docker compose 子命令，请确认本机 Docker 版本支持 compose v2。'
    }

    if (-not (Test-Path -LiteralPath $composeFile)) {
        throw "未找到 compose 模板: $composeFile"
    }

    if (-not (Test-Path -LiteralPath $envFile)) {
        Write-Warning "未找到环境变量文件: $envFile。脚本会继续执行，但 NEWAPI_* 与 LITELLM_MASTER_KEY 可能为空。"
    }
}

function Get-ComposeBaseArgs {
    <#
    .SYNOPSIS
    生成统一的 compose 基础参数。
    .OUTPUTS
    System.String[]
    返回 `docker` 后续应接收的 compose 参数数组。
    #>
    $args = @(
        'compose'
        '-f'
        $composeFile
        '--project-directory'
        $scriptDir
    )

    # `--env-file` 既用于 compose 插值，也用于让文档中的原生命令与脚本行为保持一致。
    if (Test-Path -LiteralPath $envFile) {
        $args += @('--env-file', $envFile)
    }

    return $args
}

function Read-LiteLLMEnvFile {
    <#
    .SYNOPSIS
    读取 LiteLLM 本地环境变量文件中的简单 KEY=value 配置。
    .PARAMETER Path
    `.env.local` 文件路径。
    .OUTPUTS
    System.Collections.Hashtable
    返回按变量名索引的环境变量值；不存在的文件返回空表。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $values
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmedLine = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine.StartsWith('#')) {
            continue
        }

        $separatorIndex = $trimmedLine.IndexOf('=')
        if ($separatorIndex -lt 1) {
            continue
        }

        $name = $trimmedLine.Substring(0, $separatorIndex).Trim()
        $value = $trimmedLine.Substring($separatorIndex + 1).Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        $values[$name] = $value
    }

    return $values
}

function Get-LiteLLMModelSyncPlan {
    <#
    .SYNOPSIS
    计算 LiteLLM 配置模型与当前数据库模型之间的同步计划。
    .PARAMETER ConfiguredModels
    从 `litellm.local.yaml` 读取的目标 `model_list`。
    .PARAMETER CurrentModels
    从 `/model/info` 读取的当前模型列表。
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    返回 Create、Delete、Keep 三组操作，调用方据此执行 API 请求。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$ConfiguredModels,

        [Parameter(Mandatory = $true)]
        [object[]]$CurrentModels
    )

    $configuredByName = @{}
    foreach ($model in $ConfiguredModels) {
        if ($null -eq $model.model_name) {
            continue
        }

        $configuredByName[[string]$model.model_name] = $model
    }

    $create = New-Object System.Collections.Generic.List[object]
    $delete = New-Object System.Collections.Generic.List[object]
    $keep = New-Object System.Collections.Generic.List[object]
    $managedCurrentByName = @{}
    foreach ($currentModel in $CurrentModels) {
        if ($null -eq $currentModel.model_name -or $null -eq $currentModel.model_info) {
            continue
        }

        $modelInfo = $currentModel.model_info
        if ($null -ne $modelInfo.PSObject.Properties['litellm_sync_managed'] -and [bool]$modelInfo.litellm_sync_managed) {
            $managedCurrentByName[[string]$currentModel.model_name] = $currentModel
        }
    }

    foreach ($currentModel in $CurrentModels) {
        $currentName = [string]$currentModel.model_name
        $modelId = if ($null -ne $currentModel.model_info) { $currentModel.model_info.id } else { $null }
        $isManaged = $false
        if ($null -ne $currentModel.model_info -and $null -ne $currentModel.model_info.PSObject.Properties['litellm_sync_managed']) {
            $isManaged = [bool]$currentModel.model_info.litellm_sync_managed
        }

        if (-not $configuredByName.ContainsKey($currentName)) {
            if ($isManaged -and $modelId) {
                $delete.Add([pscustomobject]@{ id = $modelId; model_name = $currentName })
            }
            else {
                $keep.Add($currentModel)
            }
            continue
        }

        $configuredModel = $configuredByName[$currentName]
        if ($isManaged -and $modelId) {
            $keep.Add($currentModel)
        }
        elseif ($managedCurrentByName.ContainsKey($currentName)) {
            continue
        }
        else {
            $create.Add($configuredModel)
        }
    }

    foreach ($configuredModel in $ConfiguredModels) {
        if ($null -eq $configuredModel.model_name) {
            continue
        }

        $configuredName = [string]$configuredModel.model_name
        if (-not $managedCurrentByName.ContainsKey($configuredName)) {
            $create.Add($configuredModel)
            continue
        }

    }

    return [pscustomobject]@{
        Create = @($create.ToArray())
        Delete = @($delete.ToArray())
        Keep   = @($keep.ToArray())
    }
}

function Invoke-LiteLLMApi {
    <#
    .SYNOPSIS
    调用 LiteLLM 管理 API，并统一注入 master key 鉴权头。
    .PARAMETER Method
    HTTP 方法。
    .PARAMETER BaseUrl
    LiteLLM Proxy 基础地址，例如 `http://127.0.0.1:34000`。
    .PARAMETER Path
    API 路径，例如 `/model/new`。
    .PARAMETER MasterKey
    LiteLLM master key。
    .PARAMETER Body
    可选 JSON 请求体对象。
    .OUTPUTS
    System.Object
    返回 `Invoke-RestMethod` 解析后的响应对象。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('GET', 'POST')]
        [string]$Method,

        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$MasterKey,

        [object]$Body
    )

    $headers = @{ 'x-litellm-api-key' = $MasterKey }
    $uri = "{0}{1}" -f $BaseUrl.TrimEnd('/'), $Path
    $request = @{
        Method      = $Method
        Uri         = $uri
        Headers     = $headers
        ErrorAction = 'Stop'
    }

    if ($PSBoundParameters.ContainsKey('Body')) {
        $request.ContentType = 'application/json'
        $request.Body = $Body | ConvertTo-Json -Depth 64
    }

    return Invoke-RestMethod @request
}

function ConvertFrom-LiteLLMConfigJson {
    <#
    .SYNOPSIS
    将容器内解析出的 LiteLLM 配置 JSON 转为同步所需结构。
    .PARAMETER Json
    包含 `store_model_in_db` 与 `model_list` 的 JSON 字符串。
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    返回 StoreModelInDb 与 Models；Models 会标记为脚本托管，便于后续只清理本脚本写入的模型。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Json
    )

    $config = $Json | ConvertFrom-Json
    $models = @($config.model_list)
    foreach ($model in $models) {
        if ($null -eq $model.PSObject.Properties['model_info'] -or $null -eq $model.model_info) {
            $model | Add-Member -NotePropertyName 'model_info' -NotePropertyValue ([pscustomobject]@{}) -Force
        }

        $model.model_info | Add-Member -NotePropertyName 'litellm_sync_managed' -NotePropertyValue $true -Force
    }

    return [pscustomobject]@{
        StoreModelInDb = [bool]$config.store_model_in_db
        Models         = $models
    }
}

function Get-LiteLLMConfigForSync {
    <#
    .SYNOPSIS
    通过容器内 Python 解析当前挂载的 LiteLLM YAML 配置。
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    返回 `store_model_in_db` 与已标记托管来源的 `model_list`。
    #>
    $json = & docker 'exec' 'litellm' 'python' '-c' @'
import json
import yaml

with open('/app/config.yaml', 'r', encoding='utf-8') as config_file:
    config = yaml.safe_load(config_file) or {}

print(json.dumps({
    'store_model_in_db': bool((config.get('general_settings') or {}).get('store_model_in_db')),
    'model_list': config.get('model_list') or []
}, ensure_ascii=False))
'@
    if ($LASTEXITCODE -ne 0) {
        throw '读取容器内 /app/config.yaml 失败，请确认 litellm 容器已启动且配置可解析。'
    }

    return ConvertFrom-LiteLLMConfigJson -Json $json
}

function Invoke-LiteLLMModelSync {
    <#
    .SYNOPSIS
    用 `litellm.local.yaml` 中的 `model_list` 同步 LiteLLM 数据库模型列表。
    .PARAMETER EnvFilePath
    `.env.local` 文件路径，用于读取 `LITELLM_MASTER_KEY` 与端口。
    .OUTPUTS
    System.Management.Automation.PSCustomObject
    返回本次同步计划与执行统计。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$EnvFilePath
    )

    $envValues = Read-LiteLLMEnvFile -Path $EnvFilePath
    $masterKey = if ($envValues.ContainsKey('LITELLM_MASTER_KEY')) { $envValues.LITELLM_MASTER_KEY } else { $env:LITELLM_MASTER_KEY }
    if ([string]::IsNullOrWhiteSpace($masterKey)) {
        throw '未找到 LITELLM_MASTER_KEY，请在 .env.local 或当前环境变量中配置后重试。'
    }

    $hostPort = if ($envValues.ContainsKey('LITELLM_HOST_PORT') -and -not [string]::IsNullOrWhiteSpace($envValues.LITELLM_HOST_PORT)) {
        $envValues.LITELLM_HOST_PORT
    }
    else {
        '34000'
    }
    $baseUrl = "http://127.0.0.1:$hostPort"

    $config = Get-LiteLLMConfigForSync
    if (-not $config.StoreModelInDb) {
        Write-Host 'general_settings.store_model_in_db 未开启，当前模型直接来自配置文件，无需同步数据库模型列表。'
        return [pscustomobject]@{
            BaseUrl  = $baseUrl
            Skipped  = $true
            Reason   = 'store_model_in_db=false'
            Plan     = $null
        }
    }

    $configuredModels = $config.Models
    $currentResponse = Invoke-LiteLLMApi -Method 'GET' -BaseUrl $baseUrl -Path '/model/info?return_wildcard_routes=true' -MasterKey $masterKey
    $currentModels = if ($null -ne $currentResponse.data) { @($currentResponse.data) } else { @() }
    $plan = Get-LiteLLMModelSyncPlan -ConfiguredModels $configuredModels -CurrentModels $currentModels

    foreach ($model in $plan.Delete) {
        Write-Host "删除旧模型: $($model.model_name) ($($model.id))"
        Invoke-LiteLLMApi -Method 'POST' -BaseUrl $baseUrl -Path '/model/delete' -MasterKey $masterKey -Body @{ id = $model.id } | Out-Null
    }

    foreach ($model in $plan.Create) {
        Write-Host "写入配置模型: $($model.model_name)"
        Invoke-LiteLLMApi -Method 'POST' -BaseUrl $baseUrl -Path '/model/new' -MasterKey $masterKey -Body $model | Out-Null
    }

    Write-Host "模型同步完成: 新增/替换 $($plan.Create.Count)，删除 $($plan.Delete.Count)，保留 $($plan.Keep.Count)。"
    return [pscustomobject]@{
        BaseUrl = $baseUrl
        Plan    = $plan
    }
}

function Invoke-DockerCompose {
    <#
    .SYNOPSIS
    以统一参数调用 docker compose，并把底层退出码透传给调用方。
    .PARAMETER ComposeArgs
    compose 子命令参数，不包含最前面的 `docker`。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ComposeArgs
    )

    & docker @ComposeArgs
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

if ($env:PWSH_TEST_SKIP_LITELLM_START_MAIN -eq '1') {
    return
}

Assert-DockerComposeReady

$normalizedAction = $Action.ToLowerInvariant()
$composeArgs = Get-ComposeBaseArgs

switch ($normalizedAction) {
    'help' {
        Show-Usage
        exit 0
    }
    '-h' {
        Show-Usage
        exit 0
    }
    '--help' {
        Show-Usage
        exit 0
    }
    'up' {
        $composeArgs += @('up', '-d')
        $composeArgs += $ExtraArgs
    }
    'down' {
        $composeArgs += @('down')
        $composeArgs += $ExtraArgs
    }
    'restart' {
        $composeArgs += @('restart', 'litellm')
        $composeArgs += $ExtraArgs
    }
    'logs' {
        # 默认跟随单个 LiteLLM 服务日志，符合最常见的排查场景。
        $composeArgs += @('logs', '-f', 'litellm')
        $composeArgs += $ExtraArgs
    }
    'ps' {
        $composeArgs += @('ps')
        $composeArgs += $ExtraArgs
    }
    'pull' {
        $composeArgs += @('pull', 'litellm')
        $composeArgs += $ExtraArgs
    }
    'sync-models' {
        Invoke-LiteLLMModelSync -EnvFilePath $envFile | Out-Null
        exit 0
    }
    default {
        Write-Host "不支持的操作: $Action" -ForegroundColor Red
        Show-Usage
        exit 1
    }
}

Invoke-DockerCompose -ComposeArgs $composeArgs
