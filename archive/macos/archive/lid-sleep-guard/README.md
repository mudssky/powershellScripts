# 合盖 caffeinate 轮询守卫归档

本目录归档曾尝试的 LaunchAgent 合盖轮询守卫方案。

## 归档原因

- macOS 合盖后会很快进入 sleep，用户态 LaunchAgent 的 `StartInterval` 不一定能在合盖到睡眠之间获得执行机会。
- 一旦系统已经睡眠，LaunchAgent 轮询不会继续运行，因此无法可靠清理仍存活的 `caffeinate`。
- 实测短时间合盖已经出现 `Clamshell Sleep`，但 `caffeinate -i` 仍保持运行，说明该方案不能作为主路径。

## 后续取舍

- 主路径改为 Hammerspoon 主动睡眠快捷键。
- 快捷键先清理 `caffeinate`、关闭蓝牙并提示实际执行结果，再延迟进入睡眠。
- 自动合盖继续保留 Hammerspoon 合盖守卫，用于 RustDesk、蓝牙等低影响辅助动作。
