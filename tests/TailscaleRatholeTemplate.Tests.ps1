Set-StrictMode -Version Latest

BeforeAll {
    # 统一从仓库根目录定位模板文件，避免测试依赖当前工作目录。
    $script:RepoRoot = Join-Path $PSScriptRoot '..'
    $script:TemplateDir = Join-Path $script:RepoRoot 'config/network/rathole'
}

function script:Convert-ToLfLineEndings {
    <#
    .SYNOPSIS
        把文本统一为 LF 行尾。

    .DESCRIPTION
        GitHub Actions 在不同平台 checkout 后，原始文本断言可能拿到 LF 或 CRLF。
        这里先把行尾归一化，避免 `(?m)^...$` 这类精确行匹配被 `\r` 干扰。

    .PARAMETER Content
        待归一化的原始文本。

    .OUTPUTS
        System.String
        返回仅使用 LF 的文本。
    #>
    param(
        [AllowEmptyString()]
        [string]$Content
    )

    return $Content -replace "`r`n?", "`n"
}

Describe 'rathole template files' {
    It 'ships examples, split PM2 configs, start script, README and local ignore rules' {
        (Test-Path -LiteralPath (Join-Path $script:TemplateDir 'server.example.toml')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $script:TemplateDir 'client.example.toml')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $script:TemplateDir 'whitelist-proxy.example.toml')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $script:TemplateDir 'rathole-server.pm2.config.cjs')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $script:TemplateDir 'rathole-client.pm2.config.cjs')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $script:TemplateDir 'start.ps1')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $script:TemplateDir 'README.md')) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $script:TemplateDir '.gitignore')) | Should -Be $true
    }
}

Describe 'rathole local ignore rules' {
    It 'ignores real local TOML configs and keeps log placeholder tracked' {
        $gitignore = Convert-ToLfLineEndings -Content (Get-Content -LiteralPath (Join-Path $script:TemplateDir '.gitignore') -Raw)

        $gitignore | Should -Match '(?m)^\*\.local\.toml$'
        $gitignore | Should -Match '(?m)^logs/\*\.log$'
        $gitignore | Should -Match '(?m)^!logs/\.gitkeep$'
    }
}

Describe 'rathole TOML examples' {
    It 'documents the server side public listener and service bind addresses' {
        $server = Convert-ToLfLineEndings -Content (Get-Content -LiteralPath (Join-Path $script:TemplateDir 'server.example.toml') -Raw)

        $server | Should -Match '(?m)^\[server\]$'
        $server | Should -Match 'bind_addr = "0\.0\.0\.0:2333"'
        $server | Should -Match '(?m)^\[server\.services\.ssh_home\]$'
        $server | Should -Match 'bind_addr = "0\.0\.0\.0:5202"'
        $server | Should -Match 'replace-with-a-long-random-token'
    }

    It 'documents the client side remote server and local service addresses' {
        $client = Convert-ToLfLineEndings -Content (Get-Content -LiteralPath (Join-Path $script:TemplateDir 'client.example.toml') -Raw)

        $client | Should -Match '(?m)^\[client\]$'
        $client | Should -Match 'remote_addr = "rathole\.example\.com:2333"'
        $client | Should -Match '(?m)^\[client\.services\.ssh_home\]$'
        $client | Should -Match 'local_addr = "127\.0\.0\.1:22"'
        $client | Should -Match 'replace-with-a-long-random-token'
    }

    It 'keeps the public allowlist forwarding scenario in a dedicated example' {
        $whitelist = Convert-ToLfLineEndings -Content (Get-Content -LiteralPath (Join-Path $script:TemplateDir 'whitelist-proxy.example.toml') -Raw)

        $whitelist | Should -Match '公网白名单转发示例'
        $whitelist | Should -Match 'remote_addr = "rathole-entry\.example\.com:2333"'
        $whitelist | Should -Match '(?m)^\[client\.services\.whitelist_api\]$'
        $whitelist | Should -Match 'local_addr = "api\.allowlist-only\.example\.com:443"'
        $whitelist | Should -Not -Match '(?m)^\[server\]$'
    }
}

Describe 'rathole PM2 configs' {
    It 'uses a dedicated client ecosystem file pointing at client.local.toml' {
        $config = Convert-ToLfLineEndings -Content (Get-Content -LiteralPath (Join-Path $script:TemplateDir 'rathole-client.pm2.config.cjs') -Raw)

        $config | Should -Match "name: 'rathole-client'"
        $config | Should -Match "interpreter: 'none'"
        $config | Should -Match "process\.env\.RATHOLE_BIN \|\| 'rathole'"
        $config | Should -Match "client\.local\.toml"
        $config | Should -Match "rathole-client\.out\.log"
        $config | Should -Match "autorestart: true"
    }

    It 'uses a dedicated server ecosystem file pointing at server.local.toml' {
        $config = Convert-ToLfLineEndings -Content (Get-Content -LiteralPath (Join-Path $script:TemplateDir 'rathole-server.pm2.config.cjs') -Raw)

        $config | Should -Match "name: 'rathole-server'"
        $config | Should -Match "interpreter: 'none'"
        $config | Should -Match "process\.env\.RATHOLE_BIN \|\| 'rathole'"
        $config | Should -Match "server\.local\.toml"
        $config | Should -Match "rathole-server\.out\.log"
        $config | Should -Match "autorestart: true"
    }
}

Describe 'rathole docs' {
    It 'explains PM2 first usage, .local TOML copies and the four-layer forwarding boundary' {
        $readme = Convert-ToLfLineEndings -Content (Get-Content -LiteralPath (Join-Path $script:TemplateDir 'README.md') -Raw)

        $readme | Should -Match '裸二进制 \+ PM2'
        $readme | Should -Match 'server\.local\.toml'
        $readme | Should -Match 'client\.local\.toml'
        $readme | Should -Match 'whitelist-proxy\.example\.toml'
        $readme | Should -Match 'TCP/UDP 四层端口转发'
        $readme | Should -Match 'Nginx、Caddy 或 Traefik'
        $readme | Should -Match 'Compose 备选'
    }
}
