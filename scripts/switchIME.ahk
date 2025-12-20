 /*
windows自带输入法的id,可以通过调用windows api GetKeyboardLayout来获取
微软拼音输入法 134481924
微软日文输入法 68224017
微软英文输入法 67699721 
*/

; 设置脚本是否可以 "看见" 隐藏的窗口
DetectHiddenWindows True

IMEmap:=Map(
    "zh",134481924,
    "jp",68224017,
    "en",67699721
)
; enAppList :=[
; "pwsh.exe"
; ]
; 获取当前激活窗口所使用的IME的ID
getCurrentIMEID(){
    winID:=winGetID("A")
    ThreadID:=DllCall("GetWindowThreadProcessId", "UInt", WinID, "UInt", 0)
    InputLocaleID:=DllCall("GetKeyboardLayout", "UInt", ThreadID, "UInt")
    return InputLocaleID
}
; 使用IMEID激活对应的输入法
switchIMEbyID(IMEID){
    winTitle:=WinGetTitle("A")
    PostMessage(0x50, 0, IMEID,, WinTitle )
}

; 可以用于判断微软拼音是否是英文模式
isEnglishMode(){
    hWnd := winGetID("A")
    result := SendMessage(
        0x283, ; Message : WM_IME_CONTROL
        0x001, ; wParam : IMC_GETCONVERSIONMODE
        0, ; lParam ： (NoArgs)
        , ; Control ： (Window)
        ; 获取当前输入法的模式
        ; Retrieves the default window handle to the IME class.
        "ahk_id " DllCall("imm32\ImmGetDefaultIMEWnd", "Uint", hWnd, "Uint")
    )
    ; DetectHiddenWindows Fasle
    ; 返回值是0表示是英文模式，其他值表明是中文模式
    return result == 0
}

; 切换微软拼音输入法
CapsLock & 1::{
    switchIMEbyID(IMEmap["zh"])
    ; SetCapsLockState "alwaysoff"
}
; 切换微软英文键盘
CapsLock & 2::{
    switchIMEbyID(IMEmap["en"])
    ; SetCapsLockState "alwaysoff"
}
; 切换微软日文输入法
CapsLock & 3::{
    switchIMEbyID(IMEmap["jp"])
    ; SetCapsLockState "alwaysoff"
}

switchIMEThread(){
    ; 使用窗口组实现批量窗口的监视
    GroupAdd "enAppGroup", "ahk_exe pwsh.exe" ;添加powershell
    GroupAdd "enAppGroup", "ahk_exe Code.exe" ;添加 vscode
    GroupAdd "enAppGroup", "ahk_exe WindowsTerminal.exe" ;添加windows terminal

    ; 启动定时器，每200ms检查一次窗口状态，替代死循环
    SetTimer CheckIMEStatus, 200
}

CheckIMEStatus() {
    static lastWasInGroup := false
    
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
                if (!isEnglishMode()) {
                    Send "{Shift}"
                }
            }
            lastWasInGroup := true
        } else {
            ; 如果刚才在英文组，现在切出来了，且是英文模式，则切回中文
            if (lastWasInGroup) {
                if (isEnglishMode()) {
                    Send "{Shift}"
                }
                lastWasInGroup := false
            }
        }
    } catch as e {
        ; 忽略窗口切换过程中的瞬时错误
    }
}

switchIMEThread()