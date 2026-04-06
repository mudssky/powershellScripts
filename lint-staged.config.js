export default {
  '*.{ps1,psm1,psd1}':
    'pwsh -File ./scripts/pwsh/devops/Format-PowerShellCode.ps1',
  '*.{js,jsx,ts,tsx,css,html,json,jsonc}': 'biome check --write',
  // Markdown 改为无参函数任务，避免 lint-staged 自动追加超长文件列表。
  // 实际目标由仓库脚本自行从 Git 暂存区解析，并折算为“根目录文件 + 父目录”集合，
  // 从而只启动一个 rumdl 进程完成扫描与修复。
  '*.md': () => 'node ./scripts/run-rumdl-staged.mjs',
  '*.py': ['uvx ruff check --fix', 'uvx ruff format'],
  '*.lua': 'stylua',
  '**/*.ipynb': ['nbstripout'],
}
