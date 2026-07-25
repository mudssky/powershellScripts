# Windows 远程装机调研

## 结论

三平台混合场景选择 Ansible。Windows 自动化优先使用运行在 Tailscale 可信网络内的 WinRM/PSRP；OpenSSH 保留为人工维护通道或兼容备选。

这里的“远程装机”指 Windows 已安装且网络可达之后的软件安装、系统配置和持续维护。若目标机还没有 Windows、网络或任何远程管理通道，需要先通过 WinPE、`Autounattend.xml`、PXE、预制镜像、厂商 BMC 或一次性现场操作完成首次引导，Ansible 无法从零建立连接。

## 已确认前置条件

Windows 目标机交付给 Ansible 前必须满足：

1. Windows 已安装并完成首次开机设置。
2. 已接入网络和 Tailscale，控制端能够解析或访问目标机。
3. 已有一个可远程使用的管理员账户。
4. 已启用 WinRM/PSRP，或安装了受 Ansible 支持的 Microsoft OpenSSH。
5. 防火墙仅向 Tailscale 网络或可信管理网放行管理入口。
6. 自动化凭据存放在 Ansible Vault 或外部 secret 中，不写入 Git inventory。

## 推荐执行链路

```text
Windows 系统/镜像
  -> 网络与 Tailscale
  -> WinRM/PSRP 管理通道
  -> Ansible 连通性验证
  -> 管理员机器阶段
  -> 必要时重启并等待恢复
  -> 普通用户 Stage 1
  -> JSON 验证与幂等重跑
```

### 1. 首次引导

使用镜像、WinPE/PXE、`Autounattend.xml` 或人工操作安装 Windows，创建目标用户和自动化管理员，接入 Tailscale，并建立第一个远程管理通道。

此阶段不应依赖 Ansible，因为目标机在管理通道建立之前不可达。

### 2. 建立 Windows 自动化通道

推荐使用 WinRM/PSRP：

- 启用 PowerShell Remoting 和 WinRM 服务，并设置为开机启动。
- 使用 HTTPS listener 和 NTLM，本地非域账户不依赖 Kerberos/AD。
- listener 默认端口为 `5986`，只绑定当前 Tailscale IP，不使用监听所有接口的 `Address='*'`。
- 禁止把 `AllowUnencrypted=true` 作为正式配置。
- 不修改 Windows 防火墙的全局启用/关闭状态。防火墙启用时添加仅允许 Tailscale 入口的规则；防火墙关闭时仍验证 `5986` 未监听 LAN/Wi-Fi 地址。
- OpenSSH 可以继续服务人工终端，但不作为 MVP 的唯一 Windows 自动化通道。

推荐 inventory 连接参数：

```yaml
ansible_connection: psrp
ansible_psrp_protocol: https
ansible_port: 5986
ansible_psrp_auth: ntlm
ansible_psrp_cert_validation: ignore
ansible_psrp_message_encryption: always
```

首期使用 bootstrap 创建的自签名证书，并依赖 Tailscale 节点身份与仅绑定 Tailscale IP 的 listener 限制入口。后续可升级为控制端信任的证书，不影响 playbook 的权限分层。

控制端使用 macOS、Linux 或 WSL，并安装 Ansible 与 `ansible.windows` collection。

### 3. 配置 inventory 与凭据

inventory 记录主机分组、Tailscale 主机名、连接插件和目标用户；密码、证书私钥或其他敏感值通过 Ansible Vault 或外部 secret 注入。

示意配置：

```yaml
all:
  children:
    windows:
      hosts:
        workstation-01:
          ansible_host: workstation-01.example.ts.net
      vars:
        ansible_connection: psrp
        ansible_user: ansible-admin
```

实际认证方式和 secret 名称在实现阶段确定，不在仓库中提交明文密码。

### 4. 验证远程管理基线

先验证以下条件，再执行任何安装：

- `ansible.windows.win_ping` 成功。
- PowerShell 版本、Windows 版本和架构属于仓库支持矩阵。
- 自动化账户具有机器阶段所需管理员权限。
- WinRM/PSRP 在重启后能够自动恢复。
- `5986` 只监听 Tailscale IP，LAN/Wi-Fi 地址和 `0.0.0.0` 不应成为有效监听入口。
- 临时目录可写，文件传输和 PowerShell 脚本执行正常。

### 5. 执行管理员机器阶段

管理员阶段只负责机器级组件：

- Git。
- PowerShell 7。
- 可选 AutoHotkey。
- 可选 WSL 和指定发行版。
- 其他需要管理员权限的 Windows capability、MSI、EXE、服务和防火墙配置。

使用 `ansible.windows.win_copy` 传输固定脚本或资产，使用 `ansible.windows.win_powershell` 执行受控 PowerShell。不得通过字符串拼接或任意脚本文本绕过仓库已有 allowlist、签名和 hash 校验。

### 6. 处理重启与断点续跑

机器阶段返回需要重启的状态时，使用 `ansible.windows.win_reboot`：

- 等待目标机离线。
- 等待 WinRM/PSRP 恢复。
- 执行只读 readiness 检查。
- 从未满足的步骤继续，而不是重做已经满足的机器操作。

仓库退出码 `10` 表示 Blocked 或 RestartRequired。Ansible role 需要解析结构化结果，区分“等待重启后续跑”和“缺少外部前置条件”，不能统一当作普通失败。

### 7. 执行普通用户 Stage 1

机器级组件满足后，切换到真实使用者身份执行用户级配置：

1. clone 或复用仓库目录。
2. 安装/验证 Scoop。
3. 执行根 Stage 1。
4. 部署 Profile、用户 PATH、用户应用配置和桌面自动化。

示意命令：

```powershell
pwsh ./install.ps1 `
  -Preset Core `
  -NetworkMode Direct `
  -NonInteractive
```

Full 场景改用 `-Preset Full`。Scoop、Profile、用户 PATH 等不能由管理员账户代跑，否则文件、注册表和用户目录所有权会落到错误身份。

### 8. 验证与幂等重跑

完成后执行只读验证：

```powershell
pwsh ./windows/99verifyInstall.ps1 `
  -Preset Core `
  -OutputFormat Json
```

Ansible 收集 JSON、退出码和失败步骤，生成精确重跑目标。第二次执行应跳过已满足状态，只处理缺失、Blocked 后已恢复或发生 drift 的项目。

## 与当前仓库的兼容缺口

当前 `windows/00quickstart.ps1` 不能原样作为 Ansible 远程入口：

- `windows/00quickstart.ps1:244` 拒绝从管理员进程运行，以避免用户配置被管理员身份拥有。
- `windows/00quickstart.ps1:325` 在严格非交互模式遇到机器级安装时返回 Blocked/10。
- `windows/bootstrap/WindowsBootstrap.psm1:508` 使用 `Start-Process -Verb RunAs` 请求 UAC；远程会话无法可靠点击该 UAC 窗口。

后续实现应显式提供远程编排边界，而不是弱化这些安全约束：

1. 管理员机器 role 调用无 UAC、固定 allowlist 的机器执行入口。
2. 必要时重启并等待远程通道恢复。
3. 普通用户 role 直接调用已有 Stage 1 与验证入口。
4. 保留本地 `00quickstart.ps1` 的一次 UAC 用户体验，不把本地与远程两种权限模型混为一体。

## 官方资料

- Ansible Windows WinRM: <https://docs.ansible.com/projects/ansible/latest/os_guide/windows_winrm.html>
- Ansible Windows SSH: <https://docs.ansible.com/projects/ansible/latest/os_guide/windows_ssh.html>
- `ansible.windows.win_copy`: <https://docs.ansible.com/ansible/latest/collections/ansible/windows/win_copy_module.html>
- `ansible.windows.win_powershell`: <https://docs.ansible.com/ansible/latest/collections/ansible/windows/win_powershell_module.html>
- `ansible.windows.win_reboot`: <https://docs.ansible.com/ansible/latest/collections/ansible/windows/win_reboot_module.html>

## 调研日期

2026-07-12
