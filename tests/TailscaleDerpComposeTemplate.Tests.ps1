Set-StrictMode -Version Latest

BeforeAll {
    # 统一从仓库根目录定位模板文件，避免测试依赖当前工作目录。
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:TemplateDir = Join-Path $script:RepoRoot 'config/network/tailscale/derp'
}

function script:Get-ComposeServiceBlock {
    <#
    .SYNOPSIS
        提取 compose 文件中指定服务的原始文本块。

    .DESCRIPTION
        通过服务级缩进边界截取文本，便于断言单个服务是否包含 host network、
        verify-clients 等关键配置，而不受其它服务内容干扰。

    .PARAMETER ComposePath
        compose 文件路径。

    .PARAMETER ServiceName
        需要提取的服务名。

    .OUTPUTS
        System.String
        返回服务块原始文本；若不存在则抛出异常。
    #>
    param(
        [string]$ComposePath,
        [string]$ServiceName
    )

    $lines = Get-Content -LiteralPath $ComposePath
    $startIndex = -1

    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match "^\s{2}$([regex]::Escape($ServiceName)):\s*$") {
            $startIndex = $index
            break
        }
    }

    if ($startIndex -lt 0) {
        throw "未找到 compose 服务块: $ServiceName"
    }

    $blockLines = New-Object System.Collections.Generic.List[string]
    for ($index = $startIndex; $index -lt $lines.Count; $index++) {
        if ($index -gt $startIndex -and $lines[$index] -match '^\s{2}[A-Za-z0-9\-_]+:\s*$') {
            break
        }

        $blockLines.Add($lines[$index])
    }

    return ($blockLines -join "`n")
}

Describe 'Tailscale DERP template files' {
    It 'ships the dedicated compose, Dockerfile, env example, policy template, start script and README' {
        (Test-Path -LiteralPath (Join-Path $script:TemplateDir 'compose.yaml')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $script:TemplateDir 'Dockerfile.derper')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $script:TemplateDir '.env.example')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $script:TemplateDir 'tailnet-policy.derp.example.hujson')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $script:TemplateDir 'start.ps1')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $script:TemplateDir 'README.md')) | Should -Be $true
    }
}

Describe 'Tailscale DERP compose template' {
    It 'defaults to tailscaled-auth plus verify-clients derper' {
        $composePath = Join-Path $script:TemplateDir 'compose.yaml'
        $compose = Get-Content -LiteralPath $composePath -Raw
        $tailscaledBlock = Get-ComposeServiceBlock -ComposePath $composePath -ServiceName 'tailscaled-auth'
        $derperBlock = Get-ComposeServiceBlock -ComposePath $composePath -ServiceName 'derper'

        $compose | Should -Match '(?m)^\s{2}tailscaled-auth:\s*$'
        $compose | Should -Match '(?m)^\s{2}derper:\s*$'
        $tailscaledBlock | Should -Match 'TS_AUTHKEY'
        $tailscaledBlock | Should -Match 'TS_SOCKET'
        $tailscaledBlock | Should -Match 'TS_STATE_DIR'
        $tailscaledBlock | Should -Match 'TS_AUTH_ONCE'
        $derperBlock | Should -Match 'network_mode:\s+host'
        $derperBlock | Should -Match '--verify-clients'
        $derperBlock | Should -Match '--socket=/var/run/tailscale/tailscaled\.sock'
        $derperBlock | Should -Match '--certmode=manual'
        $derperBlock | Should -Match '--hostname=\$\{DERP_PUBLIC_IP'
        $derperBlock | Should -Match '--certdir=/var/lib/derper/certs'
        $derperBlock | Should -Match '--a=:\$\{DERP_PORT:-443\}'
        $derperBlock | Should -Match '--stun-port=\$\{DERP_STUN_PORT:-3478\}'
    }
}

Describe 'Tailscale DERP env example' {
    It 'documents the minimum required deployment variables' {
        $envExample = Get-Content -LiteralPath (Join-Path $script:TemplateDir '.env.example') -Raw

        $envExample | Should -Match '(?m)^DERP_PUBLIC_IP='
        $envExample | Should -Match '(?m)^TS_AUTHKEY='
        $envExample | Should -Match '(?m)^DERP_CERTS_DIR='
        $envExample | Should -Match '(?m)^TAILSCALE_VERSION='
    }
}

Describe 'Tailscale DERP tailnet policy template' {
    It 'provides a paste-ready derpMap example for tailnet policy editing' {
        $template = Get-Content -LiteralPath (Join-Path $script:TemplateDir 'tailnet-policy.derp.example.hujson') -Raw

        $template | Should -Match 'derpMap'
        $template | Should -Match 'RegionID:\s*900'
        $template | Should -Match 'RegionCode:\s*"cn-custom"'
        $template | Should -Match 'HostName:\s*"203\.0\.113\.10"'
        $template | Should -Match 'DERPPort:\s*443'
        $template | Should -Match 'STUNPort:\s*3478'
    }
}

Describe 'Tailscale DERP docs' {
    It 'points readers to the dedicated template instead of start-container derper' {
        $doc = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'docs/cheatsheet/network/tailscale/index.md') -Raw

        $doc | Should -Match 'config/network/tailscale/derp'
        $doc | Should -Match 'docker compose --env-file .*compose\.yaml .*up -d --build'
        $doc | Should -Not -Match 'start-container\.ps1\s+-ServiceName\s+derper'
    }
}
