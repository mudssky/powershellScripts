

$modelList = @(
    @{
        ModelId = "bge-m3"
        Name    = 'bge-m3'
    },
    @{
        ModelId = "qwen3:4b"
        Name    = 'qwen3'
    },
    @{
        ModelId = "gemma3:4b"
        Name    = 'gemma3'
    }
)

foreach ($model in $modelList) {
    Write-Host "正在下载模型: $($model.Name)..." -ForegroundColor Cyan
    ollama pull $model.ModelId
}