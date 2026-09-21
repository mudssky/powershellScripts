# Shell 启动层级与 Profile 治理实施计划

## 1. 规范先行

- [ ] 新增 `.trellis/spec/shell-shared/package/startup-layers.md`，按 code-spec 七段结构记录目录职责、loader 签名、环境合同、错误矩阵、案例、测试点和 Wrong/Correct。
- [ ] 更新 `.trellis/spec/shell-shared/package/index.md`，把启动层规范加入 Pre-Development Checklist，并修正 `shared.d` 只适用于交互层的描述。
- [ ] 更新 `.trellis/spec/shell-shared/package/comment-conventions.md` 的适用路径与 `node.sh` 专属旧约束。
- [ ] 更新 `.trellis/spec/infra/package-sources.md`、`.trellis/spec/infra/linux-install-pipeline.md` 中的旧路径和内联 login block 描述。
- [ ] 规范评审通过后再修改 `shell/` 实现。

## 2. 建立基础环境层

- [ ] 新增 `shell/profile.d/`。
- [ ] 移动 `shared.d/homebrew.sh` 为 `profile.d/10-homebrew.sh`，保持 prefix 优先级与 PATH 幂等合同。
- [ ] 移动并收敛 `shared.d/package-sources.sh` 为 `profile.d/05-package-sources.sh`，source 后不遗留辅助函数。
- [ ] 从 `shared.d/node.sh` 提取 fnm、Bun、pnpm 环境到 `profile.d/20-node.sh`。
- [ ] `20-node.sh` 在非交互 shell 使用 `fnm env`，在交互 shell 使用 `fnm env --use-on-cd`；生成和 eval 任一步失败均安静降级。
- [ ] 将剩余 package.json 脚本选择功能重命名为 `shared.d/package-scripts.sh`。
- [ ] 将 Bun Zsh completion 移到 `zsh.d/` 专属片段。
- [ ] 不移动或改写真实 `shell/shared.d/env.local.sh`；保留 PowerShell 共享合同。

## 3. 重构部署与 loader

- [ ] 参数化 `ensure_dir`、`cleanup_stale_symlinks`、`sync_dir`，分别处理 `~/.profile.d` 与 `~/.bashrc.d`。
- [ ] 新增 Bash有效 login profile 选择函数，覆盖 `.bash_profile`、`.bash_login`、`.profile` 优先级。
- [ ] 提取通用 marker block 更新/删除函数，复用备份、dry-run、幂等和损坏 start marker 修复逻辑。
- [ ] 将现有 login block 内容替换为 `~/.profile.d/*.sh` loader，保留原 marker 完成迁移。
- [ ] 扫描并清理 Bash 非活动候选 profile 中的本仓受管 block。
- [ ] 将 rc loader 升级为成对 marker：先 source profile 片段，再仅在交互会话加载 `~/.bashrc.d/*.sh`。
- [ ] 迁移现有单行 rc marker，确保 marker 外用户内容逐行保留。
- [ ] 调整主流程为“同步目录成功后再更新 loader”。
- [ ] 更新 `--help`、日志和 dry-run 文案，明确 profile/interactive 两层。

## 4. 全目录启动层审计

- [ ] 按设计表逐个检查 `shell/shared.d`、`shell/bash.d`、`shell/zsh.d` 的 source 时行为。
- [ ] 确认所有 alias、补全、prompt、网络探测和 TTY 行为只从交互 loader 到达。
- [ ] 确认 profile 层无输出、无 alias/补全/函数遗留、无网络探测，重复 source 保持幂等。
- [ ] 对保留在交互层的环境片段记录依据：`env.local.sh`、`path.sh`、`java.sh`、`ai.sh`、`proxy.sh`。
- [ ] 只修复启动层违规和重复初始化；不顺带重写命令内部业务逻辑。

## 5. 行为测试与文档迁移

- [ ] 扩展 `scripts/bash/tests/deploy.test.ts`：双目录同步、Bash profile 优先级、目标迁移、legacy rc loader、损坏 marker、dry-run、备份、幂等。
- [ ] 更新 `scripts/bash/tests/linux-install-pipeline.test.ts`：从真实 profile loader 经 `profile.d` 恢复 Homebrew/fnm/Node/pnpm。
- [ ] 更新 `scripts/bash/tests/package-sources.test.ts` 与 Homebrew/Node 相关测试路径。
- [ ] 新增或调整交互/非交互 fixture，观察 fake `fnm` 参数：login 为无参数，interactive 为 `--use-on-cd`。
- [ ] 保留 `tests/ProfileLocalShellEnv.Tests.ps1` 合同，确认 PowerShell 仍读取既有 `env.local.sh`。
- [ ] 更新 `linux/INSTALL.md`、`linux/01installHomeBrew.sh`、`linux/pwsh/Test-InstallState.ps1` 及其它有效路径说明。
- [ ] 搜索并清除活动代码、测试、spec、文档中的旧 `shared.d/homebrew.sh`、`shared.d/package-sources.sh`、内联 login block 描述。

## 6. 验证顺序

1. 语法与窄测：
   - `bash -n shell/deploy.sh`
   - 对 `shell/profile.d/*.sh` 分别执行 Bash source smoke；本机有 Zsh 时执行 Zsh source smoke。
   - `pnpm exec vitest run scripts/bash/tests/deploy.test.ts --config ./scripts/bash/vitest.config.ts`
2. Bash 全量：
   - `pnpm test:bash`
3. PowerShell 影响面：
   - `pnpm test:pwsh:all`
4. 仓库门禁：
   - `pnpm qa`
5. 真实入口 smoke：
   - `bash shell/deploy.sh --dry-run --shell bash`
   - 实际运行 `bash shell/deploy.sh --shell bash`
   - `env -i HOME="$HOME" USER="$USER" SHELL=/bin/bash PATH=/usr/local/bin:/usr/bin:/bin /bin/bash -lc 'command -v node && node -v && command -v pnpm'`
   - 启动新的交互 Bash，验证 `fnm use`、项目 `.nvmrc` 自动切换、PATH 无固定版本目录抢在 multishell 前。
   - 本机有 Zsh 时重复 Zsh login/interactive smoke。


## 7. 本机缺块原因与收尾

- [ ] 对照提交 `fde35788` 的引入时间、本机 profile 备份时间和部署输出，确认当前缺块是未使用新版本部署还是被后续流程覆盖。
- [ ] 实际部署后确认有效 Bash profile 中只有一个受管 block，非活动候选无残留。
- [ ] 确认旧 `~/.bashrc.d/node.sh`、`homebrew.sh`、`package-sources.sh` dangling symlink 已清理。
- [ ] 删除测试用临时脚本或 fixture；保留能防止 profile 优先级、迁移与交互污染回归的永久行为测试。

## 8. 回滚点

- 规范提交前：只涉及任务规划，无运行时变化。
- profile 文件迁移后：若行为异常，先恢复自动生成的 profile/rc `.bak`。
- 部署重构后：可回退本次代码改动并重新运行旧版 `shell/deploy.sh`；不手工拼接两套 loader。
- 任何验证失败都修复源头，不放宽断言、不保留旧路径 shim。
