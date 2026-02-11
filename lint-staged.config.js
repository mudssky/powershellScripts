export default {
  '*.{ps1,psm1,psd1}':
    'pwsh -File ./scripts/pwsh/devops/Format-PowerShellCode.ps1',
  '*.{js,jsx,ts,tsx,css,html,json,jsonc}': 'biome check --write',
  '*.py': ['uvx ruff check --fix', 'uvx ruff format'],
  '*.lua': 'stylua',
  '**/*.ipynb': ['nbstripout'],
}
