## Windows hosts 失效 / 被 DNS 忽略排错记录

> 目标：记录一次 Windows 上 `hosts` 完全被忽略的排错过程，并给出可复用的排查步骤。文中出现的 IP（例如公网 IP）均为示例，已做脱敏处理。

---

### 1. 故障现象

- 在 `C:\Windows\System32\drivers\etc\hosts` 中新增映射，例如：

  ```text
  X.X.X.X tx         # 示例公网 IP
  127.0.0.1 tx_test
  ```

- 在 PowerShell / CMD 中访问时：

  ```powershell
  ping tx
  ping tx_test
  ```

  均报错：

  ```text
  Ping request could not find host tx_test. Please check the name and try again.
  ```

- 使用 .NET 解析同样失败：

  ```powershell
  [System.Net.Dns]::GetHostAddresses("tx_test")
  ```

  报错类似：

  ```text
  Exception calling "GetHostAddresses" with "1" argument(s): "不知道这样的主机。"
  ```

**结论：** 不仅 `ping`，连 OS 提供的 DNS 解析接口都完全“看不到” `hosts`，说明系统在解析阶段直接绕过了本地 hosts 文件。

---

### 2. 初步排除项

在正式排错前，先确认了一些常见问题都不是根因：

- 文件名正确：是 `hosts`，而不是 `hosts.txt`。
- 文件路径正确：位于 `C:\Windows\System32\drivers\etc\hosts`。
- 内容已写入：用 `type` 查看能看到新增记录。
  ```powershell
  type C:\Windows\System32\drivers\etc\hosts
  ```
- 编辑方式和格式：
  - 以管理员身份编辑。
  - 换行、空格、注释格式均正常。
- IP 有效性：
  - 即使用 `127.0.0.1 tx_test` 做回环测试依然不生效。
- 外部干扰：
  - 常见代理 / 加速器 / 杀毒软件已关闭。
- 注册表路径：
  - 未发现 `DataBasePath` 等关键项被篡改。

---

### 3. 环境确认：确保用的是系统 `ping` 与 Windows DNS

很多 “hosts 不生效” 实际问题是：**改了 Windows hosts，却在另一个环境（WSL、Git Bash 等）里测试**。本次排查中先确认这点：

```powershell
where ping
```

输出：

```text
C:\Windows\System32\PING.EXE
```

说明当前使用的是系统自带的 `ping`，不是 WSL 或 Git 环境内部的命令，可以排除“环境不一致”的问题。

---

### 4. 再确认 DNS 相关策略

使用 PowerShell 检查 NRPT（名称解析策略表）：

```powershell
Get-DnsClientNrptPolicy
```

输出为空，说明没有域策略或 NRPT 规则强制改写 DNS 解析路径，本地解析理论上应该会走 `hosts`。

此时的状态是：

- `hosts` 中有记录。
- 没有 NRPT 覆盖。
- `ping` 和 `[System.Net.Dns]::GetHostAddresses` 都解析失败。

焦点转向：**系统是否真正能读取这个 `hosts` 文件**。

---

### 5. 关键发现：hosts 文件 ACL 异常

在 `C:\Windows\System32\drivers\etc` 目录下，对比 `hosts` 和同目录中 `services` 文件的权限：

```powershell
icacls C:\Windows\System32\drivers\etc\hosts
icacls C:\Windows\System32\drivers\etc\services
```

当时输出类似：

```text
hosts:
  NT AUTHORITY\SYSTEM:(F)
  BUILTIN\Administrators:(F)
  <本机用户名>:(F)

services:
  NT AUTHORITY\SYSTEM:(I)(F)
  BUILTIN\Administrators:(I)(F)
  BUILTIN\Users:(I)(RX)
  APPLICATION PACKAGE AUTHORITY\ALL APPLICATION PACKAGES:(I)(RX)
  APPLICATION PACKAGE AUTHORITY\所有受限制的应用程序包:(I)(RX)
```

可以看到：

- `hosts`：
  - 权限都是显式设置的，**没有 `(I)` 继承标记**。
  - 仅 `SYSTEM`、Administrators 和当前用户有完全控制。
- `services`：
  - 权限来自继承 `(I)`。
  - 除了 `SYSTEM`、Administrators 外，还有 `BUILTIN\Users` 和应用程序包的只读权限。

这说明 `hosts` 的 ACL 被人为修改过，打断了目录默认权限的继承。  
DNS Client 服务通常以系统服务账号运行（例如 `Network Service` / `Local Service`），其访问权限和交互方式与当前登录用户不同。**一旦 ACL 配置不当，系统服务可能无法正常读取 `hosts` 文件**，从而导致解析行为等价于“hosts 不存在”。

**核心根因：**  
`hosts` 文件的 ACL 被修改，缺失了对普通用户和应用程序包的读取权限，并打断了继承，导致 DNS 解析服务在内部访问 `hosts` 时失败，进而完全绕过了 `hosts`。

---

### 6. 修复步骤：重置 hosts ACL

在确认问题根因在 ACL 后，采取了最保守、最安全的修复方式：**将 `hosts` 的权限重置为目录默认状态**。

在管理员 PowerShell 中：

```powershell
cd C:\Windows\System32\drivers\etc
icacls .\hosts /reset
```

`/reset` 的作用是：

- 清除文件上自定义的 ACL。
- 按所在目录的默认 ACL 重新应用，从而恢复和同目录其他系统文件一致的权限（例如 `services`）。

重置后再次对比：

```powershell
icacls .\hosts
icacls .\services
```

预期：

- `hosts` 也会带 `(I)` 标记。
- 主体和权限组合与 `services` 基本一致（`SYSTEM`、Administrators、Users、应用程序包等）。

---

### 7. 修复后的验证

ACL 重置后，重新进行验证：

1. 刷新 DNS 缓存：

   ```powershell
   ipconfig /flushdns
   ```

2. 测试 `ping`：

   ```powershell
   ping tx_test
   ```

   输出应能解析到 `127.0.0.1`，不再出现 “could not find host”。

3. 测试 .NET 解析：

   ```powershell
   [System.Net.Dns]::GetHostAddresses("tx_test")
   ```

   能成功返回 `127.0.0.1` 对应的地址对象，说明 OS 级 DNS API 已经正确加载 `hosts`。

至此，`hosts` 被完全忽略的问题修复完成。

---

### 8. 通用排错流程（可复用）

之后如果再次遇到 “Windows hosts 配置不生效 / 被忽略” 的情况，可以按以下顺序排查：

1. **确认环境**
   - `where ping` → 确认使用的是 `C:\Windows\System32\PING.EXE`。
   - 避免在 WSL、Git Bash 或容器内部测试 Windows hosts。

2. **确认文件路径和内容**
   - 路径：`C:\Windows\System32\drivers\etc\hosts`。
   - 使用 `type` 查看内容，确保记录已写入：
     ```powershell
     type C:\Windows\System32\drivers\etc\hosts
     ```

3. **确认编码与格式**
   - 建议使用 ANSI 或 UTF-8（无 BOM）。
   - 避免使用 UTF-16 等编码。
   - 域名和 IP 手动输入，避免不可见字符。

4. **查看 NRPT 和策略**
   - `Get-DnsClientNrptPolicy` → 确认没有特殊 DNS 策略覆盖。

5. **检查 DNS Client 服务**
   - `Get-Service Dnscache` → 确认服务在运行且启动类型正确。

6. **检查 ACL**
   - 对比 `hosts` 与同目录文件（如 `services`）的权限：
     ```powershell
     icacls C:\Windows\System32\drivers\etc\hosts
     icacls C:\Windows\System32\drivers\etc\services
     ```
   - 如发现 `hosts` 权限明显不同（无继承、主体缺失），执行：
     ```powershell
     cd C:\Windows\System32\drivers\etc
     icacls .\hosts /reset
     ```

7. **最终验证**
   - `ipconfig /flushdns`
   - `ping <hosts 中的测试域名>`
   - `[System.Net.Dns]::GetHostAddresses("<hosts 中的测试域名>")`

通过以上步骤，可以快速定位大部分 “hosts 不生效 / 被忽略” 问题，并在确认是 ACL 导致时通过 `/reset` 安全恢复。

