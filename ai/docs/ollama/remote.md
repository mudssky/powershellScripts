默认情况下，Ollama 为了安全，仅绑定在本地地址 (`127.0.0.1` / `localhost`)。要实现远程访问（即让局域网内的其他设备或公网设备访问），你需要修改环境变量 `OLLAMA_HOST`。

以下是针对不同操作系统的详细配置步骤：

---

### 1. Linux (使用 Systemd 服务)

如果你是在 Linux 服务器上通过官方脚本安装的，Ollama 通常作为 systemd 服务运行。

1.  **编辑服务配置**：
    运行以下命令打开编辑器：
    ```bash
    sudo systemctl edit ollama.service
    ```

2.  **添加环境变量**：
    在打开的文件中，添加以下内容（注意要在 `[Service]` 下方）：
    ```ini
    [Service]
    Environment="OLLAMA_HOST=0.0.0.0"
    ```
    *解释：`0.0.0.0` 表示允许所有 IP 地址访问。如果只想允许特定 IP，也可以填具体 IP，但通常填 `0.0.0.0` 更通用。*

3.  **保存并退出**：
    按 `Ctrl+O` 保存，`Enter` 确认，然后 `Ctrl+X` 退出（如果是 nano 编辑器）。

4.  **重启服务**：
    ```bash
    sudo systemctl daemon-reload
    sudo systemctl restart ollama
    ```

---

### 2. Windows

在 Windows 上，你需要通过系统设置添加环境变量。

1.  **退出 Ollama**：
    点击任务栏右下角的 Ollama 图标，右键选择 "Quit Ollama"。

2.  **设置环境变量**：
    *   打开“设置” -> “系统” -> “关于” -> “高级系统设置”。
    *   点击“环境变量”。
    *   在“系统变量”或“用户变量”区域，点击“新建”。
    *   **变量名**：`OLLAMA_HOST`
    *   **变量值**：`0.0.0.0`
    *   点击确定保存。

3.  **重启 Ollama**：
    从开始菜单重新启动 Ollama 应用程序。

---

### 3. macOS

macOS 的配置稍微复杂一点，因为这是通过应用启动的。

1.  打开终端，运行以下命令设置环境变量：
    ```bash
    launchctl setenv OLLAMA_HOST "0.0.0.0"
    ```

2.  **重启 Ollama 应用**：
    完全退出 Ollama（顶部菜单栏图标 -> Quit），然后重新打开 Ollama。

    *注意：这种方法在重启电脑后可能会失效。如果要永久生效，可能需要创建一个启动脚本或使用 Automator。*

---

### 4. Docker 部署 (最简单)

如果你是使用 Docker 运行 Ollama，只需要在启动命令中添加环境变量即可：

```bash
docker run -d -v ollama:/root/.ollama -p 11434:11434 --name ollama -e OLLAMA_HOST=0.0.0.0 ollama/ollama
```

---

### 5. 关键步骤：防火墙设置

**配置完上述步骤后，如果还是连不上，99% 是因为防火墙。**

*   **Linux (UFW)**:
    ```bash
    sudo ufw allow 11434/tcp
    ```
*   **Windows**:
    打开“Windows Defender 防火墙”，选择“允许应用通过防火墙”，找到 `ollama.exe` 并确保“专用”和“公用”网络都被勾选。
*   **云服务器 (AWS/阿里云/腾讯云)**:
    需要在云服务商的控制台（安全组）中放行 **TCP 11434** 端口。

---

### 6. 测试连接

在另一台电脑（或手机）的浏览器中输入：

`http://<安装Ollama电脑的IP地址>:11434`

如果显示 `Ollama is running`，则说明配置成功。

---

### ⚠️ 安全警告 (非常重要)

Ollama 原生 **没有任何用户验证机制**（没有账号密码）。

*   如果将 `OLLAMA_HOST` 设为 `0.0.0.0` 并暴露在公网（Internet），**任何人都可以使用你的显卡资源，甚至可能通过某些手段注入恶意代码**。
*   **建议方案**：
    1.  **局域网使用**：仅在受信任的家庭/公司 WiFi 下使用。
    2.  **公网使用**：请务必配合 **Nginx 反向代理**（设置 Basic Auth 密码）或者使用 **VPN / Tailscale / SSH 隧道** 进行访问，不要直接暴露端口。