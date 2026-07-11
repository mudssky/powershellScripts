# macOS 应用打不开右键修复快捷指令设计

## Problem

下载或解压得到的 `.app` 有时被 macOS Gatekeeper/quarantine 拦截，用户需要在 Finder 里选中应用后用右键动作完成诊断、清除隔离属性并尝试打开，避免每次手动复制终端命令。

## Architecture

- 新增 `macos/quick-actions/` 作为 macOS Finder 右键动作资产目录。
- 新增可安装的 Finder Quick Action/Automator workflow 项目，例如 `Fix App Open Issue.workflow`。
- 新增安装脚本，例如 `macos/08installQuickActions.zsh`，负责把仓库内 workflow 批量同步到 `~/Library/Services/`。
- workflow 内部调用仓库提供的通用分派器 `macos/quick-actions/run.zsh`，传入动作 ID（例如 `fix-app-open-issue`）和 Finder 选中路径列表。
- `macos/INSTALL.md` 新增安装步骤，说明安装、验证、使用和安全边界。

## Technical Choice

采用 Automator workflow / Finder Quick Action 作为第一版交付格式，而不是只提交 Apple Shortcuts `.shortcut` 文件。

依据：

- Apple Shortcuts 文档支持从 Finder Quick Actions 或 Services 调用快捷指令，也支持 `shortcuts run -i` 传入文件路径。
- 当前本机 `shortcuts` CLI 暴露 `run/list/view/sign`，没有显示稳定的静默导入子命令；这不利于仓库内批量安装。
- `~/Library/Services/*.workflow` 是当前用户 Finder 快捷操作/服务的可复制安装位置，更适合脚本化部署和验证；这里的 `Services` 是 macOS 历史目录名，Finder UI 仍可能显示为“快捷操作”。

## Data Flow

1. 用户在 Finder 中选择一个或多个项目。
2. 用户右键选择 Quick Actions/Services 中的“处理 macOS 应用打不开”动作。
3. workflow 把动作 ID 和选中路径作为参数传给 `run.zsh`。
4. `run.zsh` 按动作 ID 分派到具体动作脚本，例如 `fix-app-open-issue.zsh`。
5. 动作脚本逐个路径处理：
   - 输出当前处理路径。
   - 非目录或非 `.app` 路径直接跳过。
   - 执行 `/usr/sbin/spctl -a -vv "$app"` 输出 Gatekeeper 诊断。
   - 执行 `/usr/bin/codesign --verify --deep --strict --verbose=2 "$app"` 输出签名诊断。
   - 执行 `/usr/bin/xattr -dr com.apple.quarantine "$app"` 清除隔离属性。
   - 执行 `/usr/bin/open "$app"` 尝试打开应用。

## Safety Boundary

- 默认自动修复，但只处理 Finder 传入且后缀为 `.app` 的目录。
- 对非 `.app` 输入只输出跳过原因，不执行 `xattr -dr`。
- 不全局关闭 Gatekeeper，不修改系统安全策略。
- 文档明确：只对可信来源应用使用；诊断输出用于辅助判断签名和来源是否异常。
- workflow 内部 AppleScript 使用 `quoted form of` 生成 Terminal 命令参数，避免手写 shell quote 在 AppleScript 字符串中触发语法错误。

## Compatibility

- 目标平台是 macOS 当前用户环境。
- 安装脚本创建 `~/Library/Services`，并把 workflow 复制或同步进去。
- 如果 Finder 没有立即显示新动作，文档提示重新打开 Finder 窗口或重启 Finder。
- 验证脚本可以检查 workflow 是否已存在于 `~/Library/Services`，但不强制验证右键菜单 UI 是否已刷新。

## Rollback

- 删除 `~/Library/Services/<workflow-name>.workflow` 即可移除右键动作。
- 仓库安装脚本可提供 `--uninstall` 或在文档中给出删除命令；第一版优先实现 `--dry-run` 和 idempotent install，`--uninstall` 视实现复杂度决定。

## Trade-offs

- Automator workflow 比纯 `.shortcut` 更容易批量安装和验证，但 UI 上可能显示在 Services/Quick Actions，而不是 Shortcuts App 的收藏列表。
- 默认自动清除 quarantine 操作效率高，但要求用户只对可信来源应用使用；因此必须保留诊断输出和文档警示。
- 通用分派器让后续新增 Finder 快捷操作时只需要增加 action id 和处理脚本，workflow 继续保持薄入口；如果未来确实需要常驻服务，可以优先把 `run.zsh` 的分派契约迁移到 Go 二进制。
