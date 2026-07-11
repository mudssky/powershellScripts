
- [myAHKScripts](#myahkscripts)
  - [安装](#安装)
    - [1. 安装 AutoHotkey 2.0](#1-安装-autohotkey-20)
      - [注意事项](#注意事项)
    - [2. 部署脚本](#2-部署脚本)
  - [01. capslock.ahk](#01-capslockahk)
  - [02.switchIME.ahk](#02switchimeahk)
  - [03.win.ahk](#03winahk)
  - [04.鼠标连点器](#04鼠标连点器)

# myAHKScripts

存放自己编写的autohotkey脚本，全部基于v2版本的语法。
脚本统一存放在scripts目录

## 安装

### 1. 安装 AutoHotkey 2.0

Full 流水线会在 Stage 0 的一次 UAC 计划中安装 AutoHotkey v2，并在 09 中部署当前用户 Startup：

```powershell
# 从仓库根目录，以普通用户 PowerShell 运行
powershell.exe -NoProfile -File .\windows\00quickstart.ps1 -Preset Full

# 独立安装或验证兼容入口
pwsh .\scripts\ahk\install-autohotkey.ps1 -NetworkMode Direct

# 预览构建、Startup 和启动动作
pwsh .\windows\09deployAutoHotkey.ps1 -Preset Full -WhatIf
```

#### 注意事项

- 必须从普通用户 PowerShell 启动；机器安装由隔离 helper 请求 UAC。
- `NonInteractive` 缺少 AutoHotkey 时返回 Blocked/10，不弹 UAC。
- Direct 无 winget 时会下载官方 release 并校验 Authenticode 签名。
- China/Auto 缺少结构化 winget source adapter 时不会静默回退 Direct。

### 2. 部署脚本

`makeScripts.ps1` 把 `scripts` 目录与 `base.ahk` 生成稳定聚合脚本，在当前用户 Startup 创建快捷方式，并可启动最终脚本。

脚本支持 `-WhatIf`、`-NoAutoStart`、`-SkipShortcut`，以及可覆盖的 Output/Startup 路径。构建和 Startup 不需要管理员权限，也不得由提升进程执行。

默认会采用 include 的方式生成，有一个 `-ConcatNotInclude` 参数，如果传递给脚本
最后生成的ahk文件就是完整拼接的了。

## 01. capslock.ahk

定制capslock键作为修饰键
使用了官方提供的代码，完全禁用capslock键并且排除IME带来的干扰，使用capslock+esc代替capslock原来的功能。

|快捷键|功能|
|---|---|
|Capslock+t|窗口置顶toggle|
|Capslock+esc|大写锁定切换|

## 02.switchIME.ahk

提供自动切换输入法的功能。

需要把默认输入法调成微软拼音，进入特定的几个app比如vscode 或者windows terminal 就会用shift切换到英文模式，离开这些app的时候就会切换回中文模式。

|快捷键|功能|
|---|---|
|Capslock+1|切换为微软拼音输入法|
|Capslock+2|切换为微软英文键盘|
|Capslock+3|切换为微软日文输入法|

## 03.win.ahk

win相关的快捷键
定义`win+l`热键用于下班时，一键关闭一些应用程序
在数组中放入进程名即可

```ahk
offDuttiesCloseProcessArr:= ["foobar2000.exe","QQMusic.exe"]
```

## 04.鼠标连点器

| 快捷键     | 功能                                                         |
| ---------- | ------------------------------------------------------------ |
| Capslock+c | 连续点击，超过10分钟或者鼠标位移大于50停止                   |
| Capslock+r | 停止点击，重置计数器,重置鼠标指针到屏幕中心（多屏幕的时候找不到鼠标指针时好用） |
| CapsLock+m | 输入点击的时间间隔                                           |
