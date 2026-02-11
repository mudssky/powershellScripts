$script:InvokeProfileCoreLoaders = {
    $script:ProfileExtendedFeaturesLoaded = $false
    $script:userAlias = @()

    $profileRoot = $script:ProfileRoot

    if (-not $script:UseUltraMinimalProfile) {
        # 加载自定义模块 (包含 Test-EXEProgram、Set-CustomAlias 等)
        $loadModuleScript = Join-Path $profileRoot 'loadModule.ps1'
        try {
            . $loadModuleScript
        }
        catch {
            Write-Error "[profile/profile.ps1] dot-source 失败: $loadModuleScript :: $($_.Exception.Message)"
            throw
        }

        # wrapper.ps1 (yaz, Add-CondaEnv 等) 已移至 OnIdle 延迟加载（见 loadModule.ps1）

        # 自定义别名配置（配置目录）
        $userAliasScript = Join-Path $profileRoot 'config/aliases/user_aliases.ps1'
        try {
            $script:userAlias = . $userAliasScript
        }
        catch {
            Write-Error "[profile/profile.ps1] dot-source 失败: $userAliasScript :: $($_.Exception.Message)"
            throw
        }

        $script:ProfileExtendedFeaturesLoaded = $true
    }
    else {
        Write-Verbose 'UltraMinimal 模式已生效：跳过模块、包装函数与用户别名脚本加载'
    }
}
