# macOS Finder Quick Actions Contract

## Scenario: Finder 快捷操作通用分派器

### 1. Scope / Trigger

- Trigger: 在 `macos/quick-actions/` 下新增或修改 Finder 右键快捷操作、Automator workflow、`~/Library/Services/*.workflow` 安装脚本或动作分派逻辑。
- 目标：workflow 只作为 Finder UI 入口，业务逻辑放在仓库脚本中，方便验证、复用和后续替换为 Go 二进制 runner。
- 目录名说明：`~/Library/Services` 是 macOS 历史安装位置；Finder UI 可能显示为“快捷操作”或“服务”，文档应同时覆盖这两个入口名称。

### 2. Signatures

- 安装入口：

```zsh
zsh macos/11installQuickActions.zsh [--dry-run] [--uninstall]
```

- 通用分派器：

```zsh
zsh macos/quick-actions/run.zsh <action-id> [path...]
```

- 动作脚本示例：

```zsh
zsh macos/quick-actions/fix-app-open-issue.zsh [--dry-run] <app-path>...
```

### 3. Contracts

- workflow contract:
  - workflow 文件放在 `macos/quick-actions/<Name>.workflow/`。
  - 安装脚本复制 workflow 到 `~/Library/Services/<Name>.workflow`。
  - workflow 的 Run Shell Script 只负责调用 `run.zsh <action-id> "$@"`。
  - workflow 内部不要内联业务逻辑，不要直接调用具体动作脚本。
  - 覆盖现有 workflow 前必须创建可读时间戳 `.bak`；新内容先在同一文件系统的临时目录配置并通过 `plutil`，再原子替换目标。
  - 配置后的内容与目标一致时不得创建备份或重写。
- runner contract:
  - 第一个参数必须是 action id。
  - 未知 action id 返回 2，并输出可读错误。
  - 已知 action id 透传剩余参数到对应动作脚本。
- action contract:
  - 动作脚本必须自行校验 Finder 传入路径。
  - 非目标类型输入必须安全跳过，不执行破坏性操作。
  - 公共函数必须带中文注释，说明功能、入参和返回值。

### 4. Validation & Error Matrix

| 条件 | 期望行为 |
|------|----------|
| `run.zsh` 缺少 action id | 返回 2，输出 usage |
| `run.zsh` 收到未知 action id | 返回 2，输出未知动作和 usage |
| workflow 未安装 | `99verifyInstall.zsh --step desktop-integration` 失败并提示运行安装脚本 |
| workflow 命令未指向 `run.zsh` 和 action id | quick-actions 验证失败 |
| 传入非 `.app` 到 `fix-app-open-issue` | 安全跳过，返回成功 |
| 传入 `.app` 到 `fix-app-open-issue` | 输出 `spctl`、`codesign`、quarantine 状态，再按安全边界处理 |

### 5. Good/Base/Bad Cases

- Good: `workflow -> run.zsh fix-app-open-issue "$@" -> fix-app-open-issue.zsh "$@"`，业务逻辑可独立命令行验证。
- Base: 安装脚本支持 `--dry-run` 和重复安装，不删除用户其它 Services。
- Bad: 每个 workflow 都复制一段不同的 AppleScript、shell quote 和业务逻辑，后续修 bug 时需要逐个同步。

### 6. Tests Required

- 静态检查：

```zsh
zsh -n macos/11installQuickActions.zsh macos/quick-actions/run.zsh macos/quick-actions/*.zsh
plutil -lint "macos/quick-actions/Fix App Open Issue.workflow/Contents/Info.plist"
plutil -lint "macos/quick-actions/Fix App Open Issue.workflow/Contents/document.wflow"
```

- 行为检查：

```zsh
zsh macos/11installQuickActions.zsh --dry-run
zsh macos/11installQuickActions.zsh
zsh macos/99verifyInstall.zsh --step desktop-integration
zsh macos/quick-actions/run.zsh fix-app-open-issue --dry-run /tmp/not-an-app
```

- AppleScript quoting 检查：

```zsh
osascript - "/tmp/a path/run.zsh" "fix-app-open-issue" "/tmp/My App.app" <<'APPLESCRIPT'
on run argv
    if (count of argv) < 2 then return
    set commandText to "/bin/zsh " & quoted form of (item 1 of argv) & " " & quoted form of (item 2 of argv)
    repeat with i from 3 to count of argv
        set commandText to commandText & " " & quoted form of (item i of argv)
    end repeat
    return commandText
end run
APPLESCRIPT
```

### 7. Wrong vs Correct

#### Wrong

```applescript
on shellQuote(value)
    set AppleScript's text item delimiters to "'\\''"
    ...
end shellQuote
```

这种手写 quote 容易在 Automator 的 Run Shell Script 字符串中触发 AppleScript 语法错误，例如“预期是 `"`，却找到未知的记号”。

#### Correct

```applescript
set commandText to "/bin/zsh " & quoted form of (item 1 of argv) & " " & quoted form of (item 2 of argv)
repeat with i from 3 to count of argv
    set commandText to commandText & " " & quoted form of (item i of argv)
end repeat
```

AppleScript 自带 `quoted form of`，应优先使用它生成 shell 参数；workflow 内只拼 runner 和 action id，复杂逻辑放到仓库脚本中。
