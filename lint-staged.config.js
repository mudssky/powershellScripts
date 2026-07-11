export default {
  '{,!(archive)/**/}*.{ps1,psm1,psd1}':
    'pwsh -File ./scripts/pwsh/devops/Format-PowerShellCode.ps1',
  '{,!(archive)/**/}*.{js,jsx,ts,tsx,css,html,json,jsonc}':
    'biome check --write',
  // Markdown 改为无参函数任务，避免 lint-staged 自动追加超长文件列表。
  // 实际目标由仓库脚本自行从 Git 暂存区解析，并折算为“根目录文件 + 父目录”集合，
  // 从而只启动一个 rumdl 进程完成扫描与修复。
  '{,!(archive)/**/}*.md': () => 'node ./scripts/run-rumdl-staged.mjs',
  '{,!(archive)/**/}*.py': ['uvx ruff check --fix', 'uvx ruff format'],
  '{,!(archive)/**/}*.lua': 'stylua',
  '{,!(archive)/**/}*.ipynb': ['nbstripout'],
  // 安全扫描仍覆盖 archive；冷归档只退出格式化和 lint，不绕过 secret 检查。
  '*': () => 'betterleaks git --pre-commit --staged --redact -v',
}
