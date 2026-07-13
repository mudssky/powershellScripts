<#
.SYNOPSIS
    启动 WSL sshd 并运行长驻 Windows TCP relay。
.PARAMETER ConfigPath
    由 Initialize-WslSshAccess 安装的无敏感信息 JSON 配置。
.PARAMETER OutputFormat
    保留的兼容参数；长驻 task 通过状态文件报告启动结果。
.OUTPUTS
    无持续 stdout；启动状态写入与 ConfigPath 同目录的 status JSON。
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ConfigPath,
    [ValidateSet('Text', 'Json')][string]$OutputFormat = 'Json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$statusPath = [IO.Path]::ChangeExtension($ConfigPath, '.status.json')
$document = [ordered]@{
    schemaVersion = 1
    operation     = 'Relay'
    status        = 'Starting'
    exitCode      = 1
    wslIPv4       = ''
    message       = ''
}

function Write-WslSshRelayStatus {
    <#
    .SYNOPSIS
        原子写入 relay 启动状态。
    .PARAMETER Document
        schema v1 状态对象。
    .OUTPUTS
        None。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Document)

    $temporaryPath = "$statusPath.tmp"
    [IO.File]::WriteAllText($temporaryPath, ($Document | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $statusPath -Force
}

try {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "runtime config does not exist: $ConfigPath"
    }
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
    if ([int]$config.schemaVersion -ne 1 -or [string]$config.distribution -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]+$' -or
        [string]$config.listenAddress -notmatch '^\d{1,3}(?:\.\d{1,3}){3}$' -or
        [int]$config.listenPort -lt 1 -or [int]$config.listenPort -gt 65535 -or
        [int]$config.guestPort -lt 1 -or [int]$config.guestPort -gt 65535) {
        throw 'runtime config contract is invalid'
    }

    while ($true) {
        $keepalive = $null
        try {
            # wslrelay 依赖活跃的 wsl.exe 会话；keepalive 与 TCP relay 由同一个长驻 task 承载。
            $keepalive = Start-Process -FilePath wsl.exe -ArgumentList @(
        '-d', [string]$config.distribution, '--', 'sleep', 'infinity'
    ) -WindowStyle Hidden -PassThru
    if ($keepalive.HasExited) {
        throw 'cannot start persistent WSL keepalive process'
    }
    & wsl.exe -d ([string]$config.distribution) -u root -- systemctl restart ssh 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'cannot restart WSL ssh.service'
    }
    $rawAddresses = [string]((& wsl.exe -d ([string]$config.distribution) -- hostname -I 2>$null) -join ' ')
    $addresses = (($rawAddresses -replace [char]0, '').Trim() -split '\s+')
    $wslIPv4 = @($addresses | Where-Object { $_ -match '^\d{1,3}(?:\.\d{1,3}){3}$' -and $_ -notmatch '^127\.' })[0]
    if ([string]::IsNullOrWhiteSpace($wslIPv4)) {
        throw 'cannot resolve WSL IPv4'
    }

    $relayReady = $false
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    do {
        $client = New-Object Net.Sockets.TcpClient
        try {
            $client.Connect('127.0.0.1', [int]$config.guestPort)
            $relayReady = $true
        }
        catch {
            Start-Sleep -Seconds 1
        }
        finally {
            $client.Dispose()
        }
    } while (-not $relayReady -and [DateTime]::UtcNow -lt $deadline)
    if (-not $relayReady) {
        throw 'WSL localhost relay is not ready'
    }

    $relaySource = @'
using System;
using System.Net;
using System.Net.Sockets;
using System.Diagnostics;
using System.Threading;
using System.Threading.Tasks;

public static class WslSshTcpRelay
{
    public static void Run(string listenAddress, int listenPort, string targetAddress, int targetPort, int keepaliveProcessId)
    {
        var listener = new TcpListener(IPAddress.Parse(listenAddress), listenPort);
        listener.Start();
        try
        {
            while (true)
            {
                Process keepalive;
                try { keepalive = Process.GetProcessById(keepaliveProcessId); }
                catch { throw new InvalidOperationException("WSL keepalive process exited"); }
                if (keepalive.HasExited) throw new InvalidOperationException("WSL keepalive process exited");
                if (listener.Pending())
                {
                    var client = listener.AcceptTcpClient();
                    Task.Run(() => Handle(client, targetAddress, targetPort));
                }
                else
                {
                    Thread.Sleep(500);
                }
            }
        }
        finally { listener.Stop(); }
    }

    private static async Task Handle(TcpClient client, string targetAddress, int targetPort)
    {
        using (client)
        using (var target = new TcpClient())
        {
            try
            {
                await target.ConnectAsync(targetAddress, targetPort).ConfigureAwait(false);
                var incoming = client.GetStream();
                var outgoing = target.GetStream();
                await Task.WhenAny(Pump(incoming, outgoing), Pump(outgoing, incoming)).ConfigureAwait(false);
            }
            catch
            {
                // 单连接失败不能终止长驻 relay；调用方会在 SSH 层看到连接失败。
            }
        }
    }

    private static async Task Pump(NetworkStream source, NetworkStream destination)
    {
        var buffer = new byte[32768];
        while (true)
        {
            var count = await source.ReadAsync(buffer, 0, buffer.Length).ConfigureAwait(false);
            if (count == 0) return;
            await destination.WriteAsync(buffer, 0, count).ConfigureAwait(false);
            await destination.FlushAsync().ConfigureAwait(false);
        }
    }
}
'@
            if (-not ('WslSshTcpRelay' -as [type])) {
                Add-Type -TypeDefinition $relaySource -Language CSharp
            }

            $document.status = 'Running'
            $document.exitCode = 0
            $document.wslIPv4 = $wslIPv4
            $document.message = 'persistent WSL SSH TCP relay is running'
            Write-WslSshRelayStatus -Document $document
            [WslSshTcpRelay]::Run([string]$config.listenAddress, [int]$config.listenPort, '127.0.0.1', [int]$config.guestPort, [int]$keepalive.Id)
        }
        catch {
            $document.status = 'Recovering'
            $document.exitCode = 1
            $document.message = $_.Exception.Message
            Write-WslSshRelayStatus -Document $document
            if ($null -ne $keepalive -and -not $keepalive.HasExited) {
                Stop-Process -Id $keepalive.Id -Force -ErrorAction SilentlyContinue
            }
            Start-Sleep -Seconds 5
        }
    }
}
catch {
    $document.status = 'Failed'
    $document.exitCode = 1
    $document.message = $_.Exception.Message
    Write-WslSshRelayStatus -Document $document
    exit 1
}
