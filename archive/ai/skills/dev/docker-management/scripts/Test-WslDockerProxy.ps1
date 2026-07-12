#requires -Version 5.1
<#
.SYNOPSIS
诊断 WSL2 Docker Engine 的代理与网络连通性。

.DESCRIPTION
从 Windows 侧启动，在指定 WSL 发行版内检查宿主机代理端口、Docker Registry 代理访问、
Docker daemon 代理配置，以及可选的 hello-world 镜像拉取。脚本不会修改任何配置。

.PARAMETER Distro
要诊断的 WSL 发行版名称，默认值为 Ubuntu。

.PARAMETER HttpPort
Windows 代理软件的 HTTP/Mixed 代理端口，默认值为 7890。

.PARAMETER RegistryUrl
用于探活的 Docker Registry 地址，默认值为 https://registry-1.docker.io/v2/。

.PARAMETER TestDockerPull
启用后额外执行 docker pull hello-world:latest，用于确认 Docker daemon 拉取链路。

.OUTPUTS
System.String。输出分段诊断文本，供人工判断当前网络和代理状态。
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Distro = 'Ubuntu',

    [Parameter()]
    [ValidateRange(1, 65535)]
    [int]$HttpPort = 7890,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$RegistryUrl = 'https://registry-1.docker.io/v2/',

    [Parameter()]
    [switch]$TestDockerPull
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

<#
.SYNOPSIS
快速检查 Windows 本机 loopback 代理端口是否可连接。

.PARAMETER Port
要检查的 TCP 端口。

.OUTPUTS
System.Boolean。端口在 Windows loopback 上可连接时返回 True。
#>
function Test-WindowsLoopbackPort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(1, 65535)]
        [int]$Port
    )

    $client = [System.Net.Sockets.TcpClient]::new()
    try {
        $asyncResult = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if (-not $asyncResult.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds(3))) {
            return $false
        }

        $client.EndConnect($asyncResult)
        return $true
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

$bashScript = @'
#!/usr/bin/env bash
set +e

http_port="${1:-7890}"
registry_url="${2:-https://registry-1.docker.io/v2/}"
test_pull="${3:-false}"

print_section() {
  printf '\n== %s ==\n' "$1"
}

test_tcp() {
  local host="$1"
  local port="$2"
  timeout 3 bash -c "true </dev/tcp/${host}/${port}" >/dev/null 2>&1
}

probe_registry() {
  local proxy_url="$1"
  local header_file
  local error_file
  local status

  header_file="$(mktemp)"
  error_file="$(mktemp)"
  status="$(HTTP_PROXY="${proxy_url}" HTTPS_PROXY="${proxy_url}" NO_PROXY= \
    curl -sS -I -o "${header_file}" -w '%{http_code}' \
      --connect-timeout 15 --max-time 30 "${registry_url}" 2>"${error_file}")"

  printf 'proxy=%s status=%s\n' "${proxy_url}" "${status:-curl-failed}"
  sed -n '1,6p' "${header_file}"
  if [ -s "${error_file}" ]; then
    sed -n '1,3p' "${error_file}"
  fi

  rm -f "${header_file}" "${error_file}"

  case "${status}" in
    200|301|302|401) return 0 ;;
    *) return 1 ;;
  esac
}

print_section "WSL basics"
printf 'kernel: '
uname -r
printf 'default route: '
ip route show default 2>/dev/null | sed -n '1p'
printf 'resolv nameserver: '
awk '/nameserver/ {print $2; exit}' /etc/resolv.conf
printf 'host.docker.internal: '
getent hosts host.docker.internal | sed -n '1p'

nameserver="$(awk '/nameserver/ {print $2; exit}' /etc/resolv.conf)"
candidates=("127.0.0.1:${http_port}" "host.docker.internal:${http_port}")
if [ -n "${nameserver}" ]; then
  candidates+=("${nameserver}:${http_port}")
fi

print_section "WSL proxy port"
best_proxy=""
for hp in "${candidates[@]}"; do
  host="${hp%:*}"
  port="${hp##*:}"
  if test_tcp "${host}" "${port}"; then
    printf '%-32s ok\n' "${hp}"
    if [ -z "${best_proxy}" ]; then
      best_proxy="http://${host}:${port}"
    fi
  else
    printf '%-32s fail\n' "${hp}"
  fi
done

print_section "Registry via proxy"
registry_ok=1
for hp in "${candidates[@]}"; do
  host="${hp%:*}"
  port="${hp##*:}"
  if test_tcp "${host}" "${port}"; then
    if probe_registry "http://${host}:${port}"; then
      registry_ok=0
    fi
  else
    printf 'skip http://%s because TCP failed\n' "${hp}"
  fi
done

print_section "Docker daemon"
if command -v docker >/dev/null 2>&1; then
  docker --version
  docker compose version 2>/dev/null || true
  docker info 2>/dev/null | sed -n '/HTTP Proxy/,+5p'
  systemctl show --property=Environment docker 2>/dev/null || true
else
  echo 'docker command not found'
fi

if [ "${test_pull}" = "true" ]; then
  print_section "Docker pull"
  docker pull hello-world:latest
  pull_exit=$?
  if [ "${pull_exit}" -eq 0 ]; then
    docker run --rm hello-world
  fi
  exit "${pull_exit}"
fi

exit "${registry_ok}"
'@

Write-Host "== Windows proxy port =="
if (Test-WindowsLoopbackPort -Port $HttpPort) {
    Write-Host ("127.0.0.1:{0} ok" -f $HttpPort)
}
else {
    Write-Host ("127.0.0.1:{0} fail" -f $HttpPort)
}

$pullFlag = if ($TestDockerPull) { 'true' } else { 'false' }

# 通过 stdin 传递 bash，避免 Windows 路径与 WSL 参数转义造成误判。
$normalizedBashScript = $bashScript.Replace("`r`n", "`n").TrimEnd() + "`n"
$normalizedBashScript | & wsl.exe -d $Distro -- bash -s -- $HttpPort $RegistryUrl $pullFlag
exit $LASTEXITCODE
