# 固定 Pester 5.7.1：从 PowerShell Gallery nupkg 解包到只读 Modules 路径。
{
  pkgs,
}:
pkgs.stdenvNoCC.mkDerivation rec {
  pname = "pester";
  version = "5.7.1";

  src = pkgs.fetchurl {
    url = "https://www.powershellgallery.com/api/v2/package/Pester/${version}";
    # nupkg 内容 hash（nix hash file）
    hash = "sha256-SieQTGgUpfvkdY+OSYYfahmUrud7cRZaXEPANxumxYA=";
  };

  nativeBuildInputs = [ pkgs.unzip ];

  unpackPhase = ''
    runHook preUnpack
    mkdir source
    unzip -q "$src" -d source
    cd source
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    moduleRoot="$out/share/powershell/Modules/Pester/${version}"
    mkdir -p "$moduleRoot"
    # nupkg 根即模块内容；去掉 NuGet 元数据
    find . -mindepth 1 -maxdepth 1 \
      ! -name '_rels' \
      ! -name 'package' \
      ! -name '[Content_Types].xml' \
      ! -name '*.nuspec' \
      -exec cp -a {} "$moduleRoot/" \;
    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "Pester ${version} for isolated nix develop PSModulePath";
    homepage = "https://github.com/pester/Pester";
    license = licenses.asl20;
    platforms = platforms.all;
  };
}
