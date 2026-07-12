@{
    SchemaVersion = 1
    Assets        = @(
        @{
            Path   = 'windows/bootstrap/WindowsBootstrap.psm1'
            Sha256 = '4034d1b26c5f1e259d19505fbb5954070c9e7304f25621619b8cda9c1fc0cc68'
        }
        @{
            Path   = 'windows/bootstrap/Invoke-WindowsElevatedPlan.ps1'
            Sha256 = '741ed4067c497dd66957dc5b8ca2500d579a0f4c812e6bfb5de3508887c76717'
        }
        @{
            Path   = 'scripts/pwsh/misc/Invoke-PackageSourceBootstrap.ps1'
            Sha256 = '8109efb186f1e0e807b9f9123256009776a2d31044ea518997890e906aaddca3'
        }
        @{
            Path   = 'config/network/package-sources.bootstrap.env'
            Sha256 = '3c657e25dfe38d6f60aa54b2b57693365b871801ef9e0a438210a96fde858a20'
        }
        @{
            Path   = 'config/install/windows-packages.psd1'
            Sha256 = 'be8c14a9b7a9fd20c93320a4c8a1fb39189f7db8ffc5bd84ec70b4ee15b273b8'
        }
    )
}
