# Corepack 驱动的 pnpm wrapper：版本以仓库根 package.json#packageManager 为准。
{
  pkgs,
}:
pkgs.writeShellScriptBin "pnpm" ''
  set -euo pipefail
  # 用户级 cache，不在 shellHook 预取；首次实际调用才允许下载。
  export COREPACK_HOME="''${COREPACK_HOME:-$HOME/.cache/node/corepack}"
  export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  export COREPACK_ENABLE_AUTO_PIN=0
  exec ${pkgs.nodejs_24}/bin/corepack pnpm "$@"
''
