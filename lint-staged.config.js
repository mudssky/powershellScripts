export default {
  '*.{ps1,psm1,psd1}': 'pwsh -File ./scripts/Format-PowerShellCode.ps1',
  '*.{js,jsx,ts,tsx,css,html,json,jsonc}': 'biome format --write',
  '*.lua': 'stylua',
}
