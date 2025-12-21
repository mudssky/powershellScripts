/*
    功能：输入法状态管理与自动切换
    优化：使用 Class 封装，采用 ShellHook 监听窗口切换事件，替代轮询
*/

#Requires AutoHotkey v2.0

class ImeManager {
    ; Windows 输入法 ID 常量
    static IME_ID_ZH := 134481924
    static IME_ID_JP := 68224017
    static IME_ID_EN := 67699721
    
    ; 输入法映射表
    static ImeMap := Map(
        "zh", ImeManager.IME_ID_ZH,
        "jp", ImeManager.IME_ID_JP,
        "en", ImeManager.IME_ID_EN
    )

    ; 状态记录
    static LastWasInGroup := false
    
    ; 初始化方法
    static Init() {
        ; 设置脚本是否可以 "看见" 隐藏的窗口
        DetectHiddenWindows(true)
        
        ; 定义英文应用组
        GroupAdd("enAppGroup", "ahk_exe pwsh.exe")             ; PowerShell
        GroupAdd("enAppGroup", "ahk_exe Code.exe")             ; VS Code
        GroupAdd("enAppGroup", "ahk_exe WindowsTerminal.exe")  ; Windows Terminal
        
        ; 注册 ShellHook 消息以监听窗口激活事件
        DllCall("RegisterShellHookWindow", "Ptr", A_ScriptHwnd)
        msgNum := DllCall("RegisterWindowMessage", "Str", "SHELLHOOK")
        OnMessage(msgNum, ObjBindMethod(this, "OnShellMessage"))
        
        ; 立即执行一次检查
        this.CheckCurrentWindow()
    }

    ; ShellHook 消息处理
    static OnShellMessage(wParam, lParam, *) {
        ; 1 = HSHELL_WINDOWCREATED
        ; 4 = HSHELL_WINDOWACTIVATED
        ; 32772 = 0x8004 = HSHELL_RUDEAPPACTIVATED (全屏应用等)
        if (wParam == 4 || wParam == 32772) {
            this.CheckCurrentWindow()
        }
    }

    ; 核心逻辑：检查当前窗口并切换输入法
    static CheckCurrentWindow() {
        try {
            hWnd := WinActive("A")
            if (!hWnd)
                return

            ; 检查当前窗口是否在英文应用组中
            isInGroup := WinActive("ahk_group enAppGroup")

            if (isInGroup) {
                currentWinTitle := WinGetTitle(hWnd)
                ; 排除用vscode等软件编辑markdown的情况,编辑markdown的时候大部分地方使用中文
                if (!RegExMatch(currentWinTitle, "\.md")) {
                    ; 在en组app里，如果是中文模式切换成英文
                    if (!this.IsEnglishMode()) {
                        this.SendShift()
                    }
                }
                this.LastWasInGroup := true
            } else {
                ; 如果刚才在英文组，现在切出来了，且是英文模式，则切回中文
                if (this.LastWasInGroup) {
                    if (this.IsEnglishMode()) {
                        this.SendShift()
                    }
                    this.LastWasInGroup := false
                }
            }
        } catch as e {
            ; 忽略窗口切换过程中的瞬时错误
        }
    }

    ; 辅助方法：发送 Shift 键
    static SendShift() {
        Send("{Shift}")
    }

    ; 获取当前激活窗口所使用的IME的ID
    static GetCurrentIMEID() {
        winID := WinGetID("A")
        threadID := DllCall("GetWindowThreadProcessId", "UInt", winID, "UInt", 0)
        inputLocaleID := DllCall("GetKeyboardLayout", "UInt", threadID, "UInt")
        return inputLocaleID
    }

    ; 使用IMEID激活对应的输入法
    static SwitchIMEbyID(imeID) {
        try {
            winTitle := WinGetTitle("A")
            PostMessage(0x50, 0, imeID, , winTitle)
        }
    }

    ; 切换到指定语言
    static SwitchTo(lang) {
        if (this.ImeMap.Has(lang)) {
            this.SwitchIMEbyID(this.ImeMap[lang])
        }
    }

    ; 判断微软拼音是否是英文模式
    static IsEnglishMode() {
        try {
            hWnd := WinGetID("A")
            result := SendMessage(
                0x283, ; Message : WM_IME_CONTROL
                0x001, ; wParam : IMC_GETCONVERSIONMODE
                0,     ; lParam ： (NoArgs)
                ,      ; Control ： (Window)
                "ahk_id " DllCall("imm32\ImmGetDefaultIMEWnd", "Uint", hWnd, "Uint")
            )
            ; 返回值是0表示是英文模式，其他值表明是中文模式
            return result == 0
        } catch {
            return false
        }
    }
}

; 脚本启动时初始化
ImeManager.Init()

; ==================== 热键定义 ====================

; 切换微软拼音输入法 (中文)
CapsLock & 1:: ImeManager.SwitchTo("zh")

; 切换微软英文键盘
CapsLock & 2:: ImeManager.SwitchTo("en")

; 切换微软日文输入法
CapsLock & 3:: ImeManager.SwitchTo("jp")
