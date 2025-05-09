$config = @{
    Run          = @{
        Path     = "./psutils"
        # 输出测试结果对象，因为我不需要解析结果对象，所以关掉
        # PassThru = $True
        PassThru = $False
        # 多线程执行测试
        Parallel = @{
            Enabled    = $true
            MaxThreads = 4
        }
    }
    CodeCoverage = @{
        Enabled                 = $true
        Path                    = "./psutils/modules/*.psm1"
        # OutputPath   = "./coverge.xml"
        OutputFormat            = 'CoverageGutters'
        ExcludeFromCodeCoverage = @(
            ’./psutils/modules/error.psm1‘
            './psutils/modules/linux.psm1'
            './psutils/modules/network.psm1'
            './psutils/modules/proxy.psm1'
            './psutils/modules/pwsh.psm1'
        )

    }
    TestResult   = @{
        Enabled    = $true
        OutputPath = "./testResults.xml"
        # OutputFormat = 'NUnitXml'
    }

}

$newConfig = New-PesterConfiguration -Hashtable $config


$newConfig