# Nix Binary Cache 候选调研

## 目标

为 `aarch64-darwin` 与 `x86_64-linux` 的 Nix devshell 选择可验证、可回退的国内 binary cache，并排除只有 channel 镜像、缺少 binary cache 能力或平台覆盖不明确的候选。

## 调研时间与方法

- 调研日期：2026-07-12。
- 使用镜像站官方帮助页核对配置说明、平台限制和回退语义。
- 从当前 Apple Silicon macOS 对各候选的公开 `nix-cache-info` 端点执行 HTTPS 探测；延迟只表示本次网络样本，不作为长期 SLA。
- agent-reach 的 Exa 后端当前未配置，因此未使用全网语义搜索；网页证据通过 Jina Reader 读取官方页面。

## 候选结果

| 候选 | Binary cache | 本次探测 | 文档证据 | 结论 |
|---|---|---:|---|---|
| USTC | `https://mirrors.ustc.edu.cn/nix-channels/store` | HTTP 200，约 0.05s | 官方帮助页明确说明同时提供 channel 与动态 binary cache，建议与 `https://cache.nixos.org/` 并列，并说明缺失 nar 时 Nix 可回退后续 substituter | 首选候选 |
| TUNA | `https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store` | HTTP 200，约 0.14s | 官方帮助页明确提示当前不提供 nix-darwin binary cache，建议使用官方源或 SJTUG | 不作为双平台共享默认值 |
| SJTUG | `https://mirror.sjtu.edu.cn/nix-channels/store` | HTTP 200，约 0.45s | 官方镜像文档存在，但本次读取未获得完整配置、公钥或平台说明 | 保留为人工备选，实施前补证据 |
| NixOS 官方 | `https://cache.nixos.org/` | HTTP 200，约 0.46s | Nix 默认官方 binary cache | 必须保留为 fallback |

所有成功端点均返回：

```text
StoreDir: /nix/store
WantMassQuery: 1
Priority: 40
```

## 推荐方案

- 共享默认候选使用 USTC，官方 `cache.nixos.org` 保持为 fallback；不得用国内镜像完全替换官方 fallback。
- trusted key 必须来自被代理对象的有效签名链或镜像站正式公布值，不能从博客或未验证配置片段复制。
- SJTUG 只有在补齐正式配置与签名证据后才进入自动选择；TUNA 不作为 `aarch64-darwin` 与 `x86_64-linux` 的共同默认值。
- Auto/China 必须通过统一 package source transaction 写入、检查 hash 并恢复；不允许把 substituter 直接硬编码到 flake 的 `nixConfig` 后永久影响所有用户。

## 来源

- USTC：<https://mirrors.ustc.edu.cn/help/nix-channels.html>
- TUNA：<https://mirrors.tuna.tsinghua.edu.cn/help/nix-channels/>
- SJTUG：<https://mirrors.sjtug.sjtu.edu.cn/docs/nix-channels>
- Nix 官方 cache：<https://cache.nixos.org/nix-cache-info>
