param(
    [string]$projectName,
    [switch]$skipNpmInit,
    [switch]$needStyleLint,
    [switch]$needGitHooks
)

# 检查上一条命令是否执行成功，如果上一条命令失败直接退出程序,退出码1
function checkErr([string]$commandName) {
    if (-not $?) {
        # 输出执行失败信息
        write-host -ForegroundColor Red  ('checkErr: {0} exctute failed' -f $commandName)
        throw('{0} error found' -f $commandName)
        exit 1
    }
    else {
        # 上条命令执行成功后输出消息
        write-host -ForegroundColor Green  ('checkErr: {0} exctute successful' -f $commandName)
    }
}
function createAndInitProject([string]$projectName) {
    trap {
        write-host -ForegroundColor Red  'createAndInitProject failed' 
        break
    }
    if (-not (test-path -LiteralPath $projectName)) {
        mkdir $projectName
        Set-Location $projectName
        if ($skipNpmInit) {
            initProject -skipNpmInit
        }
        else {
            initProject
        }
    }
    else {
        write-host -ForegroundColor Red ('当前目录已经存在{0}，不可重复创建，请cd到目录中执行' -f $projectName)
    }
}
function initNpm([switch]$skipNpmInit) {
    if ($skipNpmInit) {
        npm init -y
            
    }
    else {
        npm init
    }
    checkErr -commandName 'npm init'
}
function initGit {
    if (-not (Test-Path -LiteralPath '.git')) {
        git init
        checkErr -commandName 'git init'
    }  
}
# 使用npm初始化项目
function initProject([switch]$skipNpmInit) {
    initNpm -skipNpmInit $skipNpmInit
         
    initGit
}
# 安装typescript
function installTypeScript {
    npm install --save-dev typescript
    checkErr -commandName installTypeScript
}
# 创建tsconfig
function setTsconfig {
    npx tsc  --init --lib 'es2015,dom'  --strict --sourceMap --rootDir src --outDir dist
    checkErr -commandName setTsconfig
}
# 如果没有eslint 配置文件，使用init进行创建，并且修改js文件使其兼容prettier
function createEslintConfig {
    trap {
        write-host -ForegroundColor Red  'createEslintConfig failed' 
        break
    }
    
    if (-not (Test-Path -Path .eslintrc*)) {
        npx eslint --init
        checkErr -commandName 'eslint init'        
    }
    # npx eslint --init
    # checkErr -commandName 'eslint init'
    $eslintjsStr = 'module.exports = ' + (node -e "let eslintconfig = require('./.eslintrc.js');if (!eslintconfig.extends.includes('prettier')){ eslintconfig.extends.push('prettier') }; console.log(eslintconfig); ")
    $eslintjsStr | Out-File -Encoding utf8 .eslintrc.js
}
function createPrettierConfig {
    # 配置prettier,当前路径没有prettier配置文件才执行
    if (-not (test-path -path .prettierrc*)) {
        '{"semi":false,"singleQuote":true}' | Out-File  -Encoding utf8 .prettierrc.json
    }
}
function installLintAndPrettier {
    # 安装eslint-config-prettier eslint prettier
    # 选择性安装stylelint-config-prettier stylelint
    param(
        [switch]$needStyleLint
    )
    if ($needStyleLint) {
        npm install --save-dev eslint-config-prettier eslint prettier stylelint-config-prettier stylelint
        checkErr -commandName 'install eslint prettier stylelint'
        # 创建stylelint配置文件
        if (-not (Test-Path -Path .stylelintrc.* )) {
            '{"extends": ["stylelint-config-standard","stylelint-config-prettier"]}' | Out-File .stylelintrc.json
        }
    }
    else {
        npm install --save-dev eslint-config-prettier eslint prettier
        checkErr -commandName 'install eslint prettier'
    }
    createPrettierConfig
    checkErr -commandName 'create prettier config'
    createEslintConfig 
    checkErr -commandName 'create eslint config'
}
# 安装husky lint-staged
function installGithooks {
    trap {
        write-host -ForegroundColor Red  'installGithooks failed' 
        break
    }
    npm install --save-dev husky lint-staged
    checkErr -commandName 'npm install --save-dev husky lint-staged'
    # 配置lint-staged
    $packageJsonHash = Get-Content package.json | ConvertFrom-Json -AsHashtable
    if ($needStyleLint) {
        $packageJsonHash["lint-staged"] = @{
            "**/*.{js,jsx}"        = "eslint", "prettier  --write";
            "**/*.{css,scss,less}" = "stylelint", "prettier  --write";
            "**/*.{vue}"           = "eslint", "stylelint", "prettier  --write";
        }
        # mv .\package.json .\package.json.back
    }
    else {
        $packageJsonHash["lint-staged"] = @{
            "**/*.{js,jsx}" = "eslint", "prettier  --write";
            "**/*.{vue}"    = "eslint", "prettier  --write";
        }
    }
    $packageJsonHash | ConvertTo-Json | Out-File -Encoding utf8 package.json
    # 添加precommithook
    npx husky install
    npx husky add .husky/pre-commit "npx lint-staged"
}



if ($projectName) {
    createAndInitProject -projectName $projectName
}
else {
    if (Test-Path -Path 'package.json') {
        initGit
    }
    else {
        initProject -skipNpmInit
    }
}
# 安装typescript本地开发依赖
installTypeScript
# 如果没有tsconfig,创建一个默认的
if (-not (test-path -path tsconfig.json)) {
    setTsconfig
}
installLintAndPrettier -needStyleLint=$needStyleLint
checkErr -commandName 'installLintAndPrettier'

if ($needGitHooks) {
    installGithooks
    checkErr -commandName 'installGithooks'
}

# 格式化比较乱的eslint配置文件
npx prettier -w .eslintrc.js