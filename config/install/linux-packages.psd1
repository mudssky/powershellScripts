@{
    SchemaVersion = 1
    Families      = @{
        debian = @{
            DistributionIds = @('debian', 'ubuntu')
            CoreSystem      = @(
                'build-essential'
                'ca-certificates'
                'curl'
                'git'
            )
            Docker         = @{
                Required     = @('docker.io')
                ComposeGroups = @(
                    @('docker-compose-v2', 'docker-compose-plugin', 'docker-compose')
                )
            }
            DesktopFonts   = @{
                Required = @(
                    'fontconfig'
                    'fonts-firacode'
                    'fonts-noto-cjk'
                )
                Optional = @('fonts-jetbrains-mono')
            }
        }
        arch   = @{
            DistributionIds = @('arch')
            CoreSystem      = @(
                'base-devel'
                'ca-certificates'
                'curl'
                'git'
            )
            Docker         = @{
                Required      = @('docker')
                ComposeGroups = @(
                    @('docker-compose')
                )
            }
            DesktopFonts   = @{
                Required = @(
                    'fontconfig'
                    'noto-fonts-cjk'
                    'ttf-firacode-nerd'
                )
                Optional = @('ttf-jetbrains-mono-nerd')
            }
        }
    }
}
