Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
    读取 AI agent prompt preset。

.DESCRIPTION
    从 prompts 目录读取 Markdown preset，并复用 psutils frontmatter 解析器返回 metadata 与正文。

.PARAMETER Name
    preset 名称，不包含 `.md` 扩展名。

.PARAMETER PromptsRoot
    prompts 目录路径。

.OUTPUTS
    PSCustomObject
    返回包含 `Name`、`Path`、`Metadata`、`Content` 的 preset 对象。
#>
function Read-AiAgentPromptPreset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$PromptsRoot
    )

    $path = Join-Path $PromptsRoot ("{0}.md" -f $Name)
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "未找到 prompt preset: $Name"
    }

    $frontMatter = Read-ConfigMarkdownFrontMatter -Path $path
    return [pscustomobject]@{
        Name     = $Name
        Path     = $path
        Metadata = $frontMatter.Metadata
        Content  = $frontMatter.Content
    }
}

<#
.SYNOPSIS
    解析最终 prompt 文本。

.DESCRIPTION
    按直接 prompt、prompt 文件或 preset 读取任务文本，并保证调用方只使用一种来源。

.PARAMETER Prompt
    直接传入的 prompt 文本。

.PARAMETER PromptFile
    prompt 文件路径。

.PARAMETER PresetName
    preset 名称。

.PARAMETER PromptsRoot
    prompts 目录路径。

.OUTPUTS
    string
    返回最终 prompt 文本。
#>
function Resolve-AiAgentPromptText {
    [CmdletBinding()]
    param(
        [string]$Prompt,
        [string]$PromptFile,
        [string]$PresetName,
        [string]$PromptsRoot
    )

    $sourceCount = @(@($Prompt, $PromptFile, $PresetName) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count
    if ($sourceCount -ne 1) {
        throw '必须且只能提供一种 prompt 来源。'
    }

    if (-not [string]::IsNullOrWhiteSpace($Prompt)) {
        return $Prompt
    }
    if (-not [string]::IsNullOrWhiteSpace($PromptFile)) {
        if (-not (Test-Path -LiteralPath $PromptFile -PathType Leaf)) {
            throw "prompt 文件不存在: $PromptFile"
        }
        return Get-Content -LiteralPath $PromptFile -Raw
    }

    return (Read-AiAgentPromptPreset -Name $PresetName -PromptsRoot $PromptsRoot).Content
}
