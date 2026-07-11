@{
    SchemaVersion = 1
    Steps         = @(
        @{
            Id        = 'sources'
            Number    = '03'
            Presets   = @('Core', 'Full')
            DependsOn = @()
            Platforms = @{
                macos   = @{ Supported = $true; Path = 'macos/03configureSources.zsh'; Runner = 'zsh'; PreviewArgument = '--dry-run' }
                linux   = @{ Supported = $true; Path = 'linux/03configureSources.sh'; Runner = 'bash'; PreviewArgument = '--dry-run' }
                windows = @{ Supported = $true; Path = 'windows/03configureSources.ps1'; Runner = 'pwsh'; PreviewArgument = '-WhatIf' }
            }
        }
        @{
            Id        = 'shell'
            Number    = '04'
            Presets   = @('Core', 'Full')
            DependsOn = @()
            Platforms = @{
                macos   = @{ Supported = $true; Path = 'macos/04deployShellConfig.zsh'; Runner = 'zsh'; PreviewArgument = '--dry-run' }
                linux   = @{ Supported = $true; Path = 'linux/04deployShellConfig.sh'; Runner = 'bash'; PreviewArgument = '--dry-run' }
                windows = @{ Supported = $false }
            }
        }
        @{
            Id        = 'core-cli'
            Number    = '05'
            Presets   = @('Core', 'Full')
            DependsOn = @('sources')
            Platforms = @{
                macos   = @{ Supported = $true; Path = 'macos/05installCoreCli.ps1'; Runner = 'pwsh'; PreviewArgument = '-WhatIf' }
                linux   = @{ Supported = $true; Path = 'linux/05installCoreCli.ps1'; Runner = 'pwsh'; PreviewArgument = '-WhatIf' }
                windows = @{ Supported = $true; Path = 'windows/05installCoreCli.ps1'; Runner = 'pwsh'; PreviewArgument = '-WhatIf' }
            }
        }
        @{
            Id        = 'fonts'
            Number    = '06'
            Presets   = @('Core', 'Full')
            DependsOn = @('sources')
            Platforms = @{
                macos   = @{ Supported = $true; Path = 'macos/06installFonts.ps1'; Runner = 'pwsh'; PreviewArgument = '-WhatIf' }
                linux   = @{ Supported = $true; Path = 'linux/06installFonts.ps1'; Runner = 'pwsh'; PreviewArgument = '-WhatIf' }
                windows = @{ Supported = $true; Path = 'windows/06installFonts.ps1'; Runner = 'pwsh'; PreviewArgument = '-WhatIf' }
            }
        }
        @{
            Id        = 'profile-tools'
            Number    = '07'
            Presets   = @('Core', 'Full')
            DependsOn = @('core-cli')
            Platforms = @{
                macos   = @{ Supported = $true; Path = 'macos/07installProfileTools.ps1'; Runner = 'pwsh'; PreviewArgument = '-WhatIf' }
                linux   = @{ Supported = $true; Path = 'linux/07installProfileTools.ps1'; Runner = 'pwsh'; PreviewArgument = '-WhatIf' }
                windows = @{ Supported = $true; Path = 'windows/07installProfileTools.ps1'; Runner = 'pwsh'; PreviewArgument = '-WhatIf' }
            }
        }
        @{
            Id        = 'full-apps'
            Number    = '08'
            Presets   = @('Full')
            DependsOn = @('sources')
            Platforms = @{
                macos   = @{ Supported = $true; Path = 'macos/08installFullApps.ps1'; Runner = 'pwsh'; PreviewArgument = '-WhatIf' }
                linux   = @{ Supported = $true; Path = 'linux/08installFullApps.ps1'; Runner = 'pwsh'; PreviewArgument = '-WhatIf' }
                windows = @{ Supported = $true; Path = 'windows/08installFullApps.ps1'; Runner = 'pwsh'; PreviewArgument = '-WhatIf' }
            }
        }
        @{
            Id        = 'platform-automation'
            Number    = '09'
            Presets   = @('Full')
            DependsOn = @('full-apps')
            Platforms = @{
                macos   = @{ Supported = $true; Path = 'macos/09deployHammerspoon.zsh'; Runner = 'zsh'; PreviewArgument = '--dry-run' }
                linux   = @{ Supported = $false }
                windows = @{ Supported = $true; Path = 'windows/09deployAutoHotkey.ps1'; Runner = 'pwsh'; PreviewArgument = '-WhatIf' }
            }
        }
        @{
            Id        = 'login-items'
            Number    = '10'
            Presets   = @('Full')
            DependsOn = @('full-apps')
            Platforms = @{
                macos   = @{ Supported = $true; Path = 'macos/10configureLoginItems.zsh'; Runner = 'zsh'; PreviewArgument = '--dry-run' }
                linux   = @{ Supported = $false }
                windows = @{ Supported = $false }
            }
        }
        @{
            Id        = 'desktop-integration'
            Number    = '11'
            Presets   = @('Full')
            DependsOn = @('full-apps')
            Platforms = @{
                macos   = @{ Supported = $true; Path = 'macos/11installQuickActions.zsh'; Runner = 'zsh'; PreviewArgument = '--dry-run' }
                linux   = @{ Supported = $false }
                windows = @{ Supported = $false }
            }
        }
        @{
            Id        = 'verify'
            Number    = '99'
            Presets   = @('Core', 'Full')
            DependsOn = @()
            Platforms = @{
                macos   = @{ Supported = $true; Path = 'macos/99verifyInstall.zsh'; Runner = 'zsh'; PreviewArgument = '' }
                linux   = @{ Supported = $true; Path = 'linux/99verifyInstall.ps1'; Runner = 'pwsh'; PreviewArgument = '' }
                windows = @{ Supported = $true; Path = 'windows/99verifyInstall.ps1'; Runner = 'pwsh'; PreviewArgument = '' }
            }
        }
    )
}
