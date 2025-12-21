/*
    功能：Windows 系统级操作增强
*/

class AppManager {
    ; 批量关闭程序
    ; 参数 processList: 包含进程名称的数组
    static CloseProcesses(processList) {
        for processName in processList {
            try {
                if (pid := ProcessExist(processName)) {
                    ProcessClose(pid)
                }
            } catch {
                ; 忽略无法关闭的进程
            }
        }
    }
}

; ==================== 热键定义 ====================

; 下班模式：批量关闭娱乐软件
#l:: {
    ; 下班应该关闭的程序列表
    targetApps := ["foobar2000.exe", "QQMusic.exe"]
    AppManager.CloseProcesses(targetApps)
}
