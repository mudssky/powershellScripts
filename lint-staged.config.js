export default {
  '*.{ps1,psm1,psd1}': 'pwsh -File ./srcipts/Format-PowerShellCode.ps1 -Path',
  '*.{js,jsx,ts,tsx,css,html,json,jsonc}': 'biome format --write',
}
