## 实施计划（修订版）

### 第一阶段：目录结构创建
1. **创建新的目录结构**
   - 创建 `scripts/pwsh/` 主目录
   - 按领域创建子目录：`media/`, `filesystem/`, `network/`, `devops/`, `misc/`
   - 创建 `bin/` 目录作为统一入口
   - **保持 `clis/` 目录不变**

### 第二阶段：脚本分类与迁移
2. **PowerShell脚本分类迁移**
   - **媒体类**：`VideoToAudio.ps1`, `concatflv.ps1`, `ffmpegPreset.ps1`, `pngCompress.ps1`, `webpCompress.ps1` → `scripts/pwsh/media/`
   - **文件系统类**：`smallFileCleaner.ps1`, `renameLegal.ps1`, `folderSize.ps1` → `scripts/pwsh/filesystem/`
   - **网络类**：`downGithub.ps1`, `startaria2c.ps1`, `downWith.ps1` → `scripts/pwsh/network/`
   - **DevOps类**：`Setup-VSCodeSSH.ps1`, `Setup-SshNoPasswd.ps1` → `scripts/pwsh/devops/`
   - **杂项类**：其余脚本 → `scripts/pwsh/misc/`

### 第三阶段：bin目录映射系统
3. **创建bin目录映射机制**
   - 创建 `bin/` 目录下的可执行脚本（Windows批处理文件）
   - 每个bin脚本作为对应实际脚本的代理，转发调用并传递参数
   - 创建统一的 `bin/run.ps1` 作为通用入口

### 第四阶段：配置与文档
4. **创建配置文件**
   - 创建 `scripts/registry.json` 记录脚本映射关系
   - 更新项目文档，说明新的目录结构和使用方法
   - 创建 `docs/scripts-index.md` 脚本索引文档

### 第五阶段：验证与清理
5. **验证与清理**
   - 测试bin目录脚本的调用功能
   - 验证参数传递正确性
   - 清理根目录的已迁移脚本文件

## 目录结构（重构后）
```
root/
├── scripts/                # 单文件脚本
│   └── pwsh/
│       ├── media/
│       ├── filesystem/
│       ├── network/
│       ├── devops/
│       └── misc/
├── bin/                    # 统一入口映射
├── clis/                   # 保持不变（多文件工程）
├── config/, docs/, profile/ # 保持现状
└── 其他现有目录...
```

## 核心特性
- **环境变量友好**：将 `bin/` 目录加入PATH后可直接调用脚本
- **参数透传**：bin脚本完整传递所有参数给实际脚本
- **保持现有结构**：`clis/` 目录完全不变
- **向后兼容**：通过bin映射保持脚本调用名称不变

## 示例映射
- `bin/video-to-audio.bat` → `scripts/pwsh/media/VideoToAudio.ps1`
- `bin/rename-legal.bat` → `scripts/pwsh/filesystem/renameLegal.ps1`
- `bin/down-github.bat` → `scripts/pwsh/network/downGithub.ps1`