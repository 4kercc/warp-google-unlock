# 🌐 WARP 多服务透明代理一键脚本

> 基于 Cloudflare WARP 实现 Google、Gemini、Netflix、ChatGPT、Claude 等 AI 与流媒体服务的**全局透明代理解锁**。无需客户端配置，服务器级别自动路由，支持多服务解锁检测、无人值守智能巡检与自动修复、内存防爆与智能换源。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)]()

---

## ✨ 功能特性

| 特性 | 说明 |
|---|---|
| 🚀 **一键安装** | 自动检测/安装 WARP 客户端、redsocks、配置 iptables 与安全路由 |
| 🌐 **多服务解锁** | 支持 Google / Gemini / ChatGPT / OpenAI API / Netflix / Claude 透明代理解锁 |
| 🔍 **多服务解锁检测** | 提供 `warp check` 一键综合检测各大 AI 及流媒体服务的连通与解锁状态 |
| 🤖 **无人值守智能修复** | 每日自动巡检 (`warp auto-fix`)，解锁失效时自动从 BGP 数据库刷新最新 IP 规则并自动修复 |
| 🛡️ **内存泄漏防护** | 自动限制 `warp-svc` 内存上限 (`MemoryMax=200M`) 与关闭冗余日志，解决原生客户端爆内存 Bug |
| ⚡ **智能镜像源加速** | 根据 VPS 所在国家/地区自动选源：中国大陆 VPS 自动选最快国内镜像，海外 VPS 保持官方 CDN |
| 🔁 **开机自启** | systemd 服务管理，服务器重启后自动恢复 |
| 📦 **完整卸载** | 一键清理所有组件、iptables 规则、systemd 服务与系统黑洞路由 |

---

## 🖥️ 系统要求

| 项目 | 要求 |
|---|---|
| 操作系统 | Ubuntu 16.04+ / Debian 9+ / CentOS 7+ / RHEL 7+ / Rocky Linux / AlmaLinux |
| 架构 | x86_64 / amd64 |
| 权限 | **root** 或 sudo |
| 网络 | 服务器能直连 Cloudflare（WARP 注册需要访问外网） |
| 依赖 | `curl`、`iptables`（脚本自动按需精简安装依赖） |

> ⚠️ **不支持** OpenVZ / LXC 容器（iptables 受限）。KVM / XEN / Hyper-V 虚拟机均支持。

---

## 🚀 快速开始

### 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/4kercc/warp-google-unlock/main/warp-google.sh) 1
```

### 查看多服务解锁状态

```bash
warp check
```

### 智能巡检与自动修复

```bash
warp auto-fix
```

### 卸载

```bash
warp uninstall
```

---

## 📖 工作原理

```
用户程序发起请求
       │
       ▼
  iptables nat OUTPUT (支持私网与本地排除)
       │
       ├─── 命中 WARP_GOOGLE  (Google / Gemini IP 段) ──┐
       ├─── 命中 WARP_NETFLIX  (Netflix IP 段)        ──┤
       └─── 命中 WARP_CHATGPT (OpenAI / Claude IP 段) ──┤
                                                          │
                                                重定向到 redsocks:12345
                                                          │
                                                通过 SOCKS5 转发
                                               127.0.0.1:40000 (WARP)
                                                          │
                                                Cloudflare WARP 出口
                                                          │
                                                   目标服务器
```

---

## 🔧 管理命令

安装完成后，使用 `warp` 命令进行日常维护管理：

| 命令 | 说明 |
|---|---|
| `warp status` | 查看运行状态（WARP 客户端 + SOCKS5 健康检查 + redsocks + iptables） |
| `warp check` | 运行 Google、Gemini、ChatGPT Web/API、Netflix、Claude 多服务解锁检测 |
| `warp auto-fix` | 智能巡检解锁状态，解锁失效时自动从 BGP 数据库刷新规则并修复 |
| `warp start` | 启动代理 |
| `warp stop` | 停止代理 |
| `warp restart` | 重启代理 |
| `warp ip` | 查看当前 IP（直连 IP vs WARP 代理 IP） |
| `warp update` | 全量 ASN 动态更新 IP 列表（高级功能） |
| `warp uninstall` | 完全卸载与清理 |

---

## 🌐 支持解锁的服务

- **Google & Gemini AI**
- **ChatGPT (Web & OpenAI API)**
- **Netflix 区域解锁**
- **Claude (Anthropic)**

---

## 🔄 智能巡检与无人值守修复机制

脚本通过 **systemd timer**（`warp-google-update.timer`）实现每日定时无人值守自动维护：

- 每天凌晨后台自动触发 `warp auto-fix` 巡检。
- 当所有 AI 和流媒体解锁均正常时，跳过更新，不抢占系统资源。
- 当检测到有任何一个服务解锁失效（如 OpenAI API 或 Gemini 变更了 IP 段）时，**系统会自动向 RIPE NCC API 实时拉取最新 BGP 路由前缀并重载修复**。

**查看定时器状态：**

```bash
systemctl status warp-google-update.timer
journalctl -u warp-google-update.service -n 20
```

---

## 🛡️ 内存与性能优化

针对 Cloudflare WARP 官方客户端 (`warp-svc`) 长期运行可能会发生的内存泄漏 Bug，脚本已自动进行防护：

1. **Systemd Cgroups 限制**：将 `warp-svc` 的最大使用内存限制为 `MemoryMax=200M`。
2. **日志级别优化**：自动配置 `set-log-level warn`，大幅降低日志写盘与 CPU 开销。
3. **精简安装 (--no-install-recommends)**：仅安装必要的核心依赖，节省约 80% 的磁盘和下载消耗。

---

## 📜 更新日志

### v3.0.0 (最新)
- 🆕 **智能巡检与自动修复 (`warp auto-fix`)**：每日定时无感检测解锁情况，失效时自动刷新 BGP 数据库并修复。
- 🆕 **多服务解锁综合检测 (`warp check`)**：一键检测 Google、Gemini、ChatGPT Web/API、Netflix、Claude 等连通与解锁状态。
- 🛡️ **内存泄漏防护**：限制 `warp-svc` 内存上限为 200M，解决后台长久运行爆内存问题。
- ⚡ **按国家/地区智能换源**：国内 VPS 自动测速换国内镜像，海外 VPS 保持官方 CDN，解决国外 VPS 误换国内源的问题。
- 🔒 **安全防环与断网防护**：重定向规则自动排除私网与本地地址，安装与启动阶段增加 SOCKS5 健康重试检查。

### v2.0.0
- 🆕 新增 Netflix、ChatGPT 多服务支持
- 🆕 动态 BGP IP 更新机制
- 🔧 iptables 链按服务独立命名

### v1.0.0
- 初始版本，支持 Google 透明代理

---

## 📄 License

[MIT License](LICENSE) © 2026
