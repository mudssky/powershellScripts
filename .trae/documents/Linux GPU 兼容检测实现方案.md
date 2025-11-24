## 目标
- 为 `Get-GpuInfo` 增强 Linux 兼容性，正确识别 NVIDIA/AMD/Intel GPU，并在可能时准确获取显存（VRAM）。
- 保持现有返回结构：`@{ HasGpu; VramGB; GpuType }`，接口不变。

## 现状与问题
- 现有实现优先通过 `nvidia-smi` 获取 NVIDIA 显存，但参数写法存在兼容性问题（`--format=csv, noheader, nounits` 多余空格，易失败），位置：`psutils/modules/hardware.psm1:27`。
- AMD 检测依赖 Windows WMI（`Win32_VideoController`），在 Linux 不可用；Linux 下缺失 AMD 显存与型号的获取。
- Intel 集显未覆盖；Linux 下常见但显存为共享内存，需合理返回。

## 方案概述
- 跨平台统一：优先尝试 NVIDIA（`nvidia-smi`），其次在 Linux 上使用 sysfs 与厂商工具（`/sys/class/drm/...`、`amd-smi`、`rocm-smi`）检测 AMD；最后识别 Intel（`i915` 驱动）。
- Windows 路径保留并微调（先试 `nvidia-smi`，再 WMI AMD 估算）。
- 多 GPU 情况：取第一张离散 GPU 的容量作为结果（与当前行为一致）。

## 详细实现
### NVIDIA（跨平台）
- 修正命令：`nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits`（去除逗号后空格）并解析首行 MB → GB（保留 1 位小数）。
- 若命令不存在或无输出，进入后续 AMD/Intel 检测。

### AMD（Linux）
- 首选 sysfs：读取 `/sys/class/drm/card*/device/mem_info_vram_total`（单位：字节），存在即返回 `VramGB = Round(bytes / 1GB, 1)`，`GpuType = "AMD"`。
- 厂商工具回退：
  - `amd-smi --showmeminfo vram`，解析 `Total VRAM Memory (B): <bytes>`；
  - `rocm-smi --showmeminfo vram --json`，解析 JSON 中的总显存。
- 型号获取（可选）：若需展示实际型号，尝试 `lspci` 提取 `VGA/Display` 描述字符串用于 `GpuType`，否则使用 "AMD"。
- 若无法获取显存但确认 AMD 存在，保守返回 `VramGB = 4` 并给出 `Write-Warning` 提示（沿用现有估算策略）。

### Intel（Linux）
- 识别方式：检查 `/sys/class/drm/card*/device/driver` 指向 `i915` 或通过 `lspci` 匹配 `Intel`。
- 返回：`HasGpu = $true`，`GpuType = "Intel"`，`VramGB = 0`（共享内存不计入 VRAM）。

### Windows AMD 路径
- 保留现有 WMI 检测与型号映射估算；结构与返回保持不变。

## 错误处理与日志
- 全流程 `try/catch`；对不可用命令与不可读文件使用 `Write-Verbose` 说明，AMD 无法准确获取显存时使用 `Write-Warning`（现有行为）。
- 最终失败返回：`@{ HasGpu = $false; VramGB = 0; GpuType = "None" }` 或在异常 catch 内 `GpuType = "Unknown"`（沿用现有）。

## 变更点列表
- 修正 `nvidia-smi` 格式参数（`hardware.psm1:27`）。
- 为 Linux 增加 AMD/Intel 检测分支：sysfs → 厂商工具 → 估算回退。
- 在函数开头加入 OS 分支（调用已有 `Get-OperatingSystem`）。
- 注释块补充 Linux 支持说明，示例更新。

## 验证
- NVIDIA（Linux）：安装 NVIDIA 驱动后，`nvidia-smi` 可用时返回正确显存。
- AMD（Linux）：具备 `amdgpu` 驱动设备时读取 sysfs 字段返回正确显存；无 sysfs 时使用 `amd-smi/rocm-smi` 验证；无工具则警告+估算。
- Intel（Linux）：`i915` 存在时返回 `HasGpu = $true`、`GpuType = "Intel"`、`VramGB = 0`。
- Windows：NVIDIA 与 WMI AMD 路径回归验证。
- 单元测试：为解析逻辑编写 Pester 测试，模拟命令输出与 sysfs 文件读取（使用 TestDrive: 或存根函数）。

## 兼容性与风险
- 不引入第三方依赖；优先使用系统文件与可选工具。
- 保障接口不变；仅在无法准确获取时警告而非抛错。
- 多 GPU 简化为第一张离散卡；后续可扩展为返回数组（不在本次范围）。

请确认该方案，我将按上述步骤实现并提交修改。