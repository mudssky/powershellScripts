BeforeAll {
    Import-Module "$PSScriptRoot\..\modules\filesystem.psm1" -Force
}

Describe "Get-Tree 函数测试" {
    BeforeAll {
        # 创建测试目录结构
        $testRoot = "$TestDrive\TreeTest"
        New-Item -Path $testRoot -ItemType Directory -Force
        New-Item -Path "$testRoot\folder1" -ItemType Directory
        New-Item -Path "$testRoot\folder2" -ItemType Directory
        New-Item -Path "$testRoot\folder1\subfolder1" -ItemType Directory
        New-Item -Path "$testRoot\file1.txt" -ItemType File
        New-Item -Path "$testRoot\file2.log" -ItemType File
        New-Item -Path "$testRoot\folder1\file3.txt" -ItemType File
        
        # 创建.gitignore文件
        $gitignoreContent = @"
# 注释行
*.log
folder2/
temp*
"@
        $gitignoreContent | Out-File -FilePath "$testRoot\.gitignore" -Encoding utf8
    }

    It "基本功能测试 - 显示目录树" {
        # 测试Get-Tree函数不抛出异常，使用AsObject避免控制台输出
        { $null = Get-Tree -Path $testRoot -MaxDepth 1 -AsObject $true } | Should -Not -Throw
    }

    It "AsObject参数测试 - 返回对象" {
        $result = Get-Tree -Path $testRoot -AsObject $true -MaxDepth 2
        $result | Should -Not -BeNullOrEmpty
        $result.Name | Should -Be "TreeTest"
        $result.IsDirectory | Should -Be $true
        $result.Children.Count | Should -BeGreaterThan 0
    }

    It "UseGitignore参数测试 - 启用gitignore过滤" {
        $result = Get-Tree -Path $testRoot -AsObject $true -UseGitignore $true -MaxDepth 2
        # 检查.log文件是否被过滤
        $logFiles = $result.Children | Where-Object { $_.Name -like "*.log" }
        $logFiles | Should -BeNullOrEmpty
        
        # 检查folder2是否被过滤
        $folder2 = $result.Children | Where-Object { $_.Name -eq "folder2" }
        $folder2 | Should -BeNullOrEmpty
    }

    It "UseGitignore参数测试 - 禁用gitignore过滤" {
        $result = Get-Tree -Path $testRoot -AsObject $true -UseGitignore $false -MaxDepth 2
        # 检查.log文件是否存在
        $logFiles = $result.Children | Where-Object { $_.Name -like "*.log" }
        $logFiles | Should -Not -BeNullOrEmpty
        
        # 检查folder2是否存在
        $folder2 = $result.Children | Where-Object { $_.Name -eq "folder2" }
        $folder2 | Should -Not -BeNullOrEmpty
    }

    It "ShowFiles参数测试" {
        $result = Get-Tree -Path $testRoot -AsObject $true -ShowFiles $false -MaxDepth 2
        # 应该只包含目录，不包含文件
        $files = $result.Children | Where-Object { -not $_.IsDirectory }
        $files | Should -BeNullOrEmpty
    }

    It "MaxDepth参数测试" {
        $result = Get-Tree -Path $testRoot -AsObject $true -MaxDepth 1
        # 深度为1时，不应该有子目录的子项
        $subfolders = $result.Children | Where-Object { $_.IsDirectory }
        foreach ($subfolder in $subfolders) {
            $subfolder.Children.Count | Should -Be 0
        }
    }

    It "Exclude参数测试" {
        $result = Get-Tree -Path $testRoot -AsObject $true -Exclude @("*.txt") -MaxDepth 2
        # 检查.txt文件是否被排除
        $txtFiles = $result.Children | Where-Object { $_.Name -like "*.txt" }
        $txtFiles | Should -BeNullOrEmpty
    }
}

Describe "Get-TreeObject 函数测试" {
    BeforeAll {
        # 创建测试目录结构
        $testRoot = "$TestDrive\TreeObjectTest"
        New-Item -Path $testRoot -ItemType Directory -Force
        New-Item -Path "$testRoot\folder1" -ItemType Directory
        New-Item -Path "$testRoot\file1.txt" -ItemType File
    }

    It "基本功能测试" {
        $result = Get-TreeObject -Path $testRoot
        $result | Should -Not -BeNullOrEmpty
        $result.Name | Should -Be "TreeObjectTest"
        $result.IsDirectory | Should -Be $true
        $result.Children.Count | Should -BeGreaterThan 0
    }

    It "返回对象结构正确" {
        $result = Get-TreeObject -Path $testRoot
        $result.PSObject.Properties.Name | Should -Contain "Name"
        $result.PSObject.Properties.Name | Should -Contain "FullPath"
        $result.PSObject.Properties.Name | Should -Contain "IsDirectory"
        $result.PSObject.Properties.Name | Should -Contain "Size"
        $result.PSObject.Properties.Name | Should -Contain "LastWriteTime"
        $result.PSObject.Properties.Name | Should -Contain "Children"
        $result.PSObject.Properties.Name | Should -Contain "TruncatedCount"
    }
}

Describe "ConvertTo-TreeJson 函数测试" {
    BeforeAll {
        # 创建测试目录结构
        $testRoot = "$TestDrive\JsonTest"
        New-Item -Path $testRoot -ItemType Directory -Force
        New-Item -Path "$testRoot\file1.txt" -ItemType File
        $treeObject = Get-TreeObject -Path $testRoot -MaxDepth 1
    }

    It "基本JSON转换测试" {
        $json = ConvertTo-TreeJson -TreeObject $treeObject
        $json | Should -Not -BeNullOrEmpty
        $json | Should -BeOfType [string]
        # 验证是否为有效JSON
        { $json | ConvertFrom-Json } | Should -Not -Throw
    }

    It "压缩JSON转换测试" {
        $json = ConvertTo-TreeJson -TreeObject $treeObject -Compress $true
        $json | Should -Not -BeNullOrEmpty
        # 压缩的JSON不应该包含换行符
        $json | Should -Not -Match "`n"
    }

    It "管道输入测试" {
        $json = $treeObject | ConvertTo-TreeJson
        $json | Should -Not -BeNullOrEmpty
        { $json | ConvertFrom-Json } | Should -Not -Throw
    }

    It "JSON内容验证" {
        $json = ConvertTo-TreeJson -TreeObject $treeObject
        $parsed = $json | ConvertFrom-Json
        $parsed.Name | Should -Be "JsonTest"
        $parsed.IsDirectory | Should -Be $true
    }
}

Describe "Get-GitignoreRules 函数测试" {
    BeforeAll {
        # 创建测试目录和.gitignore文件
        $testRoot = "$TestDrive\GitignoreTest"
        New-Item -Path $testRoot -ItemType Directory -Force
        $gitignoreContent = @"
# 这是注释
*.log
node_modules/
temp*

# 另一个注释
.env
"@
        $gitignoreContent | Out-File -FilePath "$testRoot\.gitignore" -Encoding utf8
    }

    It "读取gitignore规则" {
        $rules = Get-GitignoreRules -Path $testRoot
        $rules | Should -Not -BeNullOrEmpty
        $rules | Should -Contain "*.log"
        $rules | Should -Contain "node_modules/"
        $rules | Should -Contain "temp*"
        $rules | Should -Contain ".env"
        # 注释和空行应该被过滤掉
        $rules | Should -Not -Contain "# 这是注释"
    }

    It "没有gitignore文件时返回空数组" {
        $emptyTestRoot = "$TestDrive\EmptyTest"
        New-Item -Path $emptyTestRoot -ItemType Directory -Force
        $rules = Get-GitignoreRules -Path $emptyTestRoot
        # 检查返回值不为null
        # ($rules) | Should -Not -Be $null
        ( $null -ne $rules) | Should -Be $true
        # 检查返回值的计数为0（空数组）
        @($rules).Count | Should -Be 0
    }
}

Describe "Test-GitignoreMatch 函数测试" {
    BeforeAll {
        # 创建测试文件和目录
        $testRoot = "$TestDrive\MatchTest"
        New-Item -Path $testRoot -ItemType Directory -Force
        New-Item -Path "$testRoot\test.log" -ItemType File
        New-Item -Path "$testRoot\test.txt" -ItemType File
        New-Item -Path "$testRoot\node_modules" -ItemType Directory
        New-Item -Path "$testRoot\src" -ItemType Directory
        
        $gitignoreRules = @("*.log", "node_modules/", "temp*")
    }

    It "匹配文件扩展名规则" {
        $logFile = Get-Item "$testRoot\test.log"
        $result = Test-GitignoreMatch -Item $logFile -GitignoreRules $gitignoreRules -BasePath $testRoot
        $result | Should -Be $true
    }

    It "不匹配的文件" {
        $txtFile = Get-Item "$testRoot\test.txt"
        $result = Test-GitignoreMatch -Item $txtFile -GitignoreRules $gitignoreRules -BasePath $testRoot
        $result | Should -Be $false
    }

    It "匹配目录规则" {
        $nodeModules = Get-Item "$testRoot\node_modules"
        $result = Test-GitignoreMatch -Item $nodeModules -GitignoreRules $gitignoreRules -BasePath $testRoot
        $result | Should -Be $true
    }

    It "不匹配的目录" {
        $srcDir = Get-Item "$testRoot\src"
        $result = Test-GitignoreMatch -Item $srcDir -GitignoreRules $gitignoreRules -BasePath $testRoot
        $result | Should -Be $false
    }

    It "空规则数组" {
        $txtFile = Get-Item "$testRoot\test.txt"
        $result = Test-GitignoreMatch -Item $txtFile -GitignoreRules @() -BasePath $testRoot
        $result | Should -Be $false
    }
}

Describe "Build-TreeObject 函数测试" {
    BeforeAll {
        # 创建测试目录结构
        $testRoot = "$TestDrive\BuildTest"
        New-Item -Path $testRoot -ItemType Directory -Force
        New-Item -Path "$testRoot\folder1" -ItemType Directory
        New-Item -Path "$testRoot\file1.txt" -ItemType File
        New-Item -Path "$testRoot\folder1\file2.txt" -ItemType File
    }

    It "构建基本树对象" {
        $result = Build-TreeObject -Path $testRoot -CurrentDepth 0 -MaxDepth 2 -ShowFiles $true -ShowHidden $false -Exclude @() -MaxItems 50
        $result | Should -Not -BeNullOrEmpty
        $result.Name | Should -Be "BuildTest"
        $result.IsDirectory | Should -Be $true
        $result.Children.Count | Should -BeGreaterThan 0
    }

    It "限制深度" {
        $result = Build-TreeObject -Path $testRoot -CurrentDepth 0 -MaxDepth 1 -ShowFiles $true -ShowHidden $false -Exclude @() -MaxItems 50
        $folder1 = $result.Children | Where-Object { $_.Name -eq "folder1" }
        $folder1.Children.Count | Should -Be 0
    }

    It "排除文件" {
        $result = Build-TreeObject -Path $testRoot -CurrentDepth 0 -MaxDepth 2 -ShowFiles $false -ShowHidden $false -Exclude @() -MaxItems 50
        $files = $result.Children | Where-Object { -not $_.IsDirectory }
        $files | Should -BeNullOrEmpty
    }
}