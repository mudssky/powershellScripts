$config = @{
    Run          = @{
        Path     = "./psutils"
        # 输出测试结果对象，因为我不需要解析结果对象，所以关掉
        # PassThru = $True
        PassThru = $False
    }
    CodeCoverage = @{
        Enabled      = $true
        Path         = "./psutils/modules/*.psm1"
        # OutputPath   = "./coverge.xml"
        OutputFormat = 'CoverageGutters'
    }
    TestResult   = @{
        Enabled    = $true
        OutputPath = "./testResults.xml"
        # OutputFormat = 'NUnitXml'
    }

}

$newConfig =New-PesterConfiguration -Hashtable $config


$newConfig