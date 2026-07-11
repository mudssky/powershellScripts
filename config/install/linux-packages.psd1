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
    }
}
