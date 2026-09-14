@{
    SchemaVersion = 1
    Packages      = @{
        Git          = @{
            WingetId       = 'Git.Git'
            ReleaseApi     = 'https://api.github.com/repos/git-for-windows/git/releases/latest'
            AssetPattern   = '^Git-.*-64-bit\.exe$'
            InstallerType  = 'ExeInstaller'
        }
        PowerShell   = @{
            WingetId       = 'Microsoft.PowerShell'
            ReleaseApi     = 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest'
            AssetPattern   = '^PowerShell-.*-win-x64\.msi$'
            InstallerType  = 'MsiInstall'
        }
        AutoHotkey   = @{
            WingetId       = 'AutoHotkey.AutoHotkey'
            ReleaseApi     = 'https://api.github.com/repos/AutoHotkey/AutoHotkey/releases/latest'
            AssetPattern   = '^[^/]*_setup\.exe$'
            InstallerType  = 'ExeInstaller'
        }
    }
    Scoop         = @{
        InstallerUrl = 'https://get.scoop.sh'
        FontBucket   = 'nerd-fonts'
        Fonts        = @('JetBrainsMono-NF', 'FiraCode-NF')
    }
    Wsl           = @{
        DefaultDistribution = 'Ubuntu-24.04'
        Settings            = @(
            @{ Section = 'wsl2'; Name = 'networkingMode'; Value = 'mirrored'; MinimumBuild = 22621 }
            @{ Section = 'experimental'; Name = 'sparseVhd'; Value = 'true'; MinimumBuild = 22621 }
            @{ Section = 'experimental'; Name = 'hostAddressLoopback'; Value = 'true'; MinimumBuild = 22621 }
        )
    }
}
