{
  description = "powershellScripts 显式 nix develop 开发环境（不接管宿主安装链）";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
      forAllSystems =
        f:
        nixpkgs.lib.genAttrs systems (
          system:
          f (
            import nixpkgs {
              inherit system;
              config = { };
            }
          )
        );
    in
    {
      devShells = forAllSystems (
        pkgs:
        let
          pester = import ./nix/pester.nix { inherit pkgs; };
          pnpmWrapper = import ./nix/pnpm-wrapper.nix { inherit pkgs; };
          # 最小构建工具：qa / cargo / bash 测试
          buildTools = with pkgs; [
            gnumake
            python3
            bash
            coreutils
            findutils
            gnugrep
            gnused
            gawk
            which
            curl
            cacert
            unzip
          ];
        in
        {
          default = pkgs.mkShell {
            name = "powershellScripts-dev";
            packages = with pkgs; [
              nodejs_24
              pnpmWrapper
              powershell
              rustc
              cargo
              clippy
              rustfmt
              git
              pester
            ]
            ++ buildTools;

            shellHook = ''
              # 进程级变量；不写 HOME/rc，不自动 install
              export NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
              export SSL_CERT_FILE="$NIX_SSL_CERT_FILE"
              export COREPACK_HOME="''${COREPACK_HOME:-$HOME/.cache/node/corepack}"
              export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
              export COREPACK_ENABLE_AUTO_PIN=0
              export PSModulePath="${pester}/share/powershell/Modules''${PSModulePath:+:$PSModulePath}"

              echo "powershellScripts nix develop"
              echo "  node:  $(command -v node)  -> $(node -v 2>/dev/null || true)"
              echo "  pnpm:  $(command -v pnpm)"
              echo "  pwsh:  $(command -v pwsh)"
              echo "  rustc: $(command -v rustc) -> $(rustc --version 2>/dev/null || true)"
              echo "  Pester module root prepended from Nix store"
            '';
          };
        }
      );
    };
}
