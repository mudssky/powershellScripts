$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$containerPort = '4000'

# 使用参数数组调用 docker，避免反引号续行导致参数被 PowerShell 错误拆分。
# LiteLLM 官方镜像会通过环境变量 PORT 拼接 uvicorn 启动命令，未显式传入时会报 "--port requires an argument"。
$dockerArgs = @(
    'run'
    '-d'
    '--name'
    'litellm'
    '-p'
    "34000:$containerPort"
    '-e'
    "PORT=$containerPort"
    '-e'
    "DATABASE_URL=postgresql://postgres:12345678@host.docker.internal:5432/litellm"
    '-v'
    "$scriptDir/newapi.yaml:/app/config.yaml"
    '--env-file'
    "$scriptDir/../.env.local"
    '--restart'
    'unless-stopped'
    'docker.litellm.ai/berriai/litellm:main-latest'
)

docker @dockerArgs
