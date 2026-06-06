# WSL Docker Wrapper Spec

> 本规范记录 `psutils/modules/docker.psm1` 中 WSL Docker wrapper 的路径转换与测试契约。

## Scenario: WSL Docker Path Conversion

### 1. Scope / Trigger

- Trigger: 修改 `ConvertTo-WslDockerPath`、`ConvertTo-WslDockerArgument`、`Invoke-WslDocker`、`Enable-WslDockerWrapper` 或 `psutils/tests/docker.Tests.ps1`。
- Scope: Windows PowerShell 会话把 `docker` 命令代理到 WSL 发行版内的 Docker Engine，期间只转换需要进入 WSL 的宿主机路径。
- Design intent: wrapper 必须支持 Windows 调用场景，同时 Pester 测试要能在 Windows、Linux、macOS CI 上稳定验证同一契约。

### 2. Signatures

- `ConvertTo-WslDockerPath -Path <string> [-WslCommand <string>] [-Distro <string>]`
- `ConvertTo-WslDockerVolumeSpec -VolumeSpec <string> [-WslCommand <string>] [-Distro <string>]`
- `ConvertTo-WslDockerMountSpec -MountSpec <string> [-WslCommand <string>] [-Distro <string>]`
- `ConvertTo-WslDockerArgument -Arguments <object[]> -Distro <string> [-WslCommand <string>]`
- `Invoke-WslDocker -Distro <string> -Arguments <object[]> [-WslCommand <string>]`

### 3. Contracts

- Windows drive paths like `C:\data` and UNC paths must be converted through `wslpath -a`.
- Existing relative paths must first resolve against the current PowerShell location.
- If the resolved path is still POSIX style, return that absolute POSIX path directly instead of calling `wslpath`.
- Non-existing relative values remain unchanged so service names, image names and container names are not treated as paths.
- `-f`、`--file`、`--env-file`、`--project-directory` accept path values.
- `-v`、`--volume` convert only the host source side.
- `--mount` and `type=bind,...` convert only `src=` or `source=`.
- `Invoke-WslDocker` passes the converted current location through `wsl.exe -d <distro> --cd <path> -- docker ...`; if conversion leaves a Windows drive path, fallback working directory is `~`.

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|-----------|-------------------|
| `Path` is null, empty or whitespace | Return original value |
| Existing relative path on Windows | Resolve to absolute Windows path, then call `wslpath -a` |
| Existing relative path on Linux/macOS CI | Resolve to absolute POSIX path and return it directly |
| POSIX absolute path | Return original POSIX path |
| Non-existing relative token | Return original token |
| `wslpath` throws or exits non-zero | Write verbose diagnostic and return original input |
| Working directory stays Windows drive path | Use `~` for `--cd` |

### 5. Good/Base/Bad Cases

- Good: `docker compose -f .\docker-compose.yml --env-file=.env -v .\data:/data:ro` converts the three host paths on Windows and returns absolute POSIX paths unchanged on Linux/macOS CI.
- Base: `docker compose restart api` keeps `api` unchanged even if a file with that name exists.
- Bad: Treating every slash-prefixed path as Windows input creates invalid values like `/mnt//tmp/...` in non-Windows CI.

### 6. Tests Required

- `psutils/tests/docker.Tests.ps1` must cover wrapper enablement, raw `docker run`, compose file/env/volume/mount conversion, env path forwarding, and non-path positional arguments.
- Path conversion tests must derive expected current working directory through `ConvertTo-WslDockerPath` instead of hard-coding one OS-specific path.
- Test doubles for `wsl.exe` must model Windows drive paths and POSIX paths separately.

### 7. Wrong vs Correct

#### Wrong

```powershell
# 在 Linux/macOS CI 中会把 /tmp/demo 错转成 /mnt//mp/demo
& wsl.exe -d Ubuntu-24.04 -- wslpath -a '/tmp/demo'
```

问题：POSIX 路径不是 Windows 宿主机路径，不能交给按盘符模拟的 `wslpath` 测试替身。

#### Correct

```powershell
$resolvedPath = Resolve-Path -LiteralPath '.\data'
if ($resolvedPath.Path -match '^[A-Za-z]:[\\/]' -or $resolvedPath.Path -match '^\\\\') {
    & wsl.exe -d Ubuntu-24.04 -- wslpath -a $resolvedPath.Path
}
else {
    $resolvedPath.Path
}
```

理由：只转换 Windows 宿主机路径，跨平台 CI 里的 POSIX 路径保持原生形态。
