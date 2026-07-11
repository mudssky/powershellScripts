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
            @{ Section = 'wsl2'; Name = 'memory'; Value = '16GB'; MinimumBuild = 19045 }
            @{ Section = 'wsl2'; Name = 'processors'; Value = '4'; MinimumBuild = 19045 }
            @{ Section = 'wsl2'; Name = 'swap'; Value = '8GB'; MinimumBuild = 19045 }
            @{ Section = 'wsl2'; Name = 'localhostForwarding'; Value = 'true'; MinimumBuild = 19045 }
            @{ Section = 'wsl2'; Name = 'guiApplications'; Value = 'true'; MinimumBuild = 19045 }
            @{ Section = 'wsl2'; Name = 'nestedVirtualization'; Value = 'true'; MinimumBuild = 22000 }
            @{ Section = 'wsl2'; Name = 'networkingMode'; Value = 'mirrored'; MinimumBuild = 22621 }
            @{ Section = 'wsl2'; Name = 'dnsTunneling'; Value = 'true'; MinimumBuild = 22621 }
            @{ Section = 'wsl2'; Name = 'firewall'; Value = 'true'; MinimumBuild = 22621 }
            @{ Section = 'wsl2'; Name = 'autoProxy'; Value = 'true'; MinimumBuild = 22621 }
            @{ Section = 'experimental'; Name = 'autoMemoryReclaim'; Value = 'gradual'; MinimumBuild = 22621 }
            @{ Section = 'experimental'; Name = 'sparseVhd'; Value = 'true'; MinimumBuild = 22621 }
            @{ Section = 'experimental'; Name = 'hostAddressLoopback'; Value = 'true'; MinimumBuild = 22621 }
        )
    }
}
