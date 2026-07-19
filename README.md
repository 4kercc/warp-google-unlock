# 🌐 WARP 多服务透明代理一键脚本

> 基于 Cloudflare WARP 实现 Google、Netflix、ChatGPT 等服务的**全局透明代理解锁**，无需客户端配置，服务器级别自动路由，支持 IP 列表每 7 天自动从 BGP 数据库更新。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-Ubuntu%20%7C%20Debian%20%7C%20CentOS%20%7C%20RHEL-blue.svg)]()
[![Shell](https://img.shields.io/badge/Shell-Bash-green.svg)]()

---

## ✨ 功能特性

| 特性 | 说明 |
|---|---|
| 🚀 **一键安装** | 自动安装 WARP 客户端、redsocks、配置 iptables |
| 🌍 **多服务解锁** | Google / Netflix / ChatGPT 透明代理，开箱即用 |
| 🔄 **自动更新 IP** | 每 7 天从 RIPE NCC BGP 数据库自动拉取最新 IP 段 |
| 🛡️ **静态兜底** | 网络故障时自动回退到内置 IP 列表，不中断服务 |
| 🔁 **开机自启** | systemd 服务管理，服务器重启后自动恢复 |
| 📦 **完整卸载** | 一键清理所有组件、iptables 规则、systemd 服务 |

---

## 🖥️ 系统要求

| 项目 | 要求 |
|---|---|
| 操作系统 | Ubuntu 16.04+ / Debian 9+ / CentOS 7+ / RHEL 7+ / Rocky Linux / AlmaLinux |
| 架构 | x86_64 / amd64 |
| 权限 | **root** 或 sudo |
| 网络 | 服务器能直连 Cloudflare（WARP 注册需要访问外网） |
| 依赖 | `curl`、`iptables`（脚本自动安装 redsocks、cloudflare-warp） |

> ⚠️ **不支持** OpenVZ / LXC 容器（iptables 受限）。KVM / XEN / Hyper-V 虚拟机均支持。

---

## 🚀 快速开始

### 一键安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/4kercc/warp-unlock/main/warp-google.sh)
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
  iptables nat OUTPUT
       │
       ├─── 命中 WARP_GOOGLE  (Google IP 段)   ──┐
       ├─── 命中 WARP_NETFLIX  (Netflix IP 段) ──┤
       └─── 命中 WARP_CHATGPT (OpenAI IP 段)  ──┤
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

**核心组件：**

| 组件 | 作用 |
|---|---|
| **Cloudflare WARP** | 提供代理出口，SOCKS5 监听在 `40000` 端口 |
| **redsocks** | 将 TCP 流量透明转发给 WARP SOCKS5 代理（监听 `12345`）|
| **iptables** | 拦截匹配目标 IP 段的流量，重定向至 redsocks |
| **systemd timer** | 每 7 天自动重启服务，触发 BGP IP 列表更新 |
| **RIPE NCC API** | 实时 BGP 路由数据库，提供各 ASN 的最新 IP 前缀 |

---

## 🔧 管理命令

安装完成后，使用 `warp` 命令管理：

```bash
warp status      # 查看运行状态（WARP + redsocks + iptables）
warp start       # 启动代理
warp stop        # 停止代理
warp restart     # 重启代理（同时触发 IP 列表更新）
warp test        # 测试 Google 连通性
warp ip          # 查看当前 IP（直连 vs WARP）
warp uninstall   # 完全卸载
```

---

## 🌐 支持解锁的服务

| 服务 | 数据源 ASN | IP 来源 |
|---|---|---|
| **Google** | AS15169 | RIPE NCC BGP 实时前缀 |
| **Netflix** | AS2906 | RIPE NCC BGP 实时前缀 |
| **ChatGPT / OpenAI** | AS401518 + Cloudflare AS13335 | RIPE NCC BGP 实时前缀 |

### 添加自定义服务

编辑 `/usr/local/bin/warp-google`，在 `SERVICE_IPS` 关联数组中添加新条目：

```bash
# 示例：添加 Twitter/X
SERVICE_IPS[twitter]="
104.244.42.0/24
104.244.46.0/24
"
```

或者利用内置函数从 RIPE 拉取任意 ASN：

```bash
# 在脚本 start() 函数中添加
update_asn_ips twitter 13414
```

然后重启服务：`warp restart`

---

## 🔄 IP 自动更新机制

脚本通过 **systemd timer** 实现定期自动更新：

```ini
# /etc/systemd/system/warp-google-update.timer
[Timer]
OnBootSec=10min        # 开机 10 分钟后首次触发
OnUnitActiveSec=7d     # 之后每 7 天触发一次
Persistent=true        # 若错过触发时间（如关机），开机后补触发
```

每次触发流程：

```
触发 warp-google restart
       │
       ├─ 1. 向 RIPE NCC API 查询各 ASN 最新 BGP 前缀
       ├─ 2. 过滤 IPv4 前缀，替换内存 IP 列表
       ├─ 3. 清空旧 iptables 链，写入新规则
       └─ 4. API 失败 → 自动回退到内置静态列表
```

**手动触发更新：**

```bash
warp restart
# 或直接触发 systemd 服务
systemctl start warp-google-update.service
```

**查看 timer 状态：**

```bash
systemctl status warp-google-update.timer
systemctl list-timers | grep warp
journalctl -u warp-google-update -n 20
```

---

## 🔁 开机自启验证

安装完成后，脚本自动检查三项开机自启状态：

```
══════ 开机自启状态 ══════
  warp-google.service     : ✓ 已开机自启
  warp-svc.service        : ✓ 已开机自启
  warp-google-update.timer: ✓ 每 7 天自动更新 IP
```

如需手动修复：

```bash
# 修复代理服务自启
systemctl enable warp-google

# 修复 WARP 客户端自启
systemctl enable warp-svc

# 修复定时更新自启
systemctl enable --now warp-google-update.timer
```

---

## 🛠️ 故障排查

### 检查服务状态

```bash
warp status                          # 综合状态
journalctl -u warp-google -n 50      # 代理服务日志
journalctl -u warp-svc -n 50         # WARP 客户端日志
journalctl -u warp-google-update -n 20  # 定时更新日志
```

### 常见问题

**❓ Google 无法访问**

```bash
# 检查 redsocks 是否运行
pgrep -x redsocks && echo "运行中" || echo "未运行"

# 检查 iptables 规则
iptables -t nat -L WARP_GOOGLE -n | head -10

# 检查 WARP 连接
warp-cli status
```

**❓ Netflix 报错"不支持的地区"**

Netflix 内容受版权区域限制。运行 `warp ip` 查看 WARP 出口 IP 的地理位置，需确保出口 IP 位于 Netflix 内容可用地区。

**❓ ChatGPT 无法访问**

部分数据中心 IP 被 OpenAI 封锁。尝试使用 `warp restart` 更新 IP 列表，或检查 WARP 出口 IP 是否属于住宅/商业 IP 段。

**❓ iptables 规则重启后丢失**

`warp-google.service` 已配置开机自启，会自动重建规则。如未恢复：

```bash
systemctl start warp-google
# 若服务未启用
systemctl enable --now warp-google
```

---

## 📁 文件清单

| 路径 | 说明 |
|---|---|
| `/usr/local/bin/warp-google` | 透明代理核心脚本（IP 列表 + iptables 逻辑）|
| `/usr/local/bin/warp` | 用户命令行管理工具 |
| `/etc/redsocks.conf` | redsocks 配置文件 |
| `/etc/systemd/system/warp-google.service` | 主代理服务 |
| `/etc/systemd/system/warp-google-update.service` | IP 更新触发服务 |
| `/etc/systemd/system/warp-google-update.timer` | 7 天自动更新定时器 |

---

## 🔒 安全说明

- 脚本仅拦截**特定 IP 段**的流量，不影响其他网络访问
- WARP 以**代理模式**运行（非 VPN 全局模式），不修改默认路由表
- iptables 规则仅作用于 `OUTPUT` 链，不影响路由转发流量
- 所有操作需要 root 权限，请确保在可信环境中运行

---

## 📊 技术架构

```
┌─────────────────────────────────────────────┐
│              RIPE NCC BGP API                │
│    (stat.ripe.net/data/announced-prefixes)   │
└───────────────────┬─────────────────────────┘
                    │ 每 7 天拉取
                    ▼
┌─────────────────────────────────────────────┐
│         warp-google-update.timer             │
│    (systemd timer / OnUnitActiveSec=7d)      │
└───────────────────┬─────────────────────────┘
                    │ 触发 restart
                    ▼
┌─────────────────────────────────────────────┐
│          /usr/local/bin/warp-google          │
│  ┌─────────────┐   ┌───────────────────┐    │
│  │ SERVICE_IPS │   │  iptables nat     │    │
│  │ [google]    │──▶│  WARP_GOOGLE      │    │
│  │ [netflix]   │──▶│  WARP_NETFLIX     │    │
│  │ [chatgpt]   │──▶│  WARP_CHATGPT     │    │
│  └─────────────┘   └────────┬──────────┘    │
└────────────────────────────┼────────────────┘
                             │ REDIRECT :12345
                             ▼
                    ┌────────────────┐
                    │   redsocks     │
                    │  :12345        │
                    └───────┬────────┘
                            │ SOCKS5
                            ▼
                    ┌────────────────┐
                    │  WARP Client   │
                    │  :40000        │
                    └───────┬────────┘
                            │
                    Cloudflare WARP 出口
```

---

## 📜 更新日志

### v2.0.0
- 🆕 新增 Netflix、ChatGPT 多服务支持
- 🆕 动态 BGP IP 更新机制（每 7 天从 RIPE NCC 自动刷新）
- 🆕 systemd timer 定时自动重启（`OnUnitActiveSec=7d`）
- 🆕 安装完成后开机自启状态检查与报告
- 🔧 iptables 链改为按服务独立命名（WARP_GOOGLE / WARP_NETFLIX / WARP_CHATGPT）
- 🔧 卸载逻辑完善，清理所有残留文件、规则和 timer
- 🔧 网络故障时自动回退到内置静态 IP 列表

### v1.0.0
- 初始版本，支持 Google 透明代理

---

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

- **新增服务**：提交新的 ASN 编号和对应测试结果
- **报告 Bug**：附上 `journalctl -u warp-google -n 100` 输出
- **文档改进**：修正或补充使用说明

---

## ⚠️ 免责声明

本项目仅供技术研究和合法用途。使用者需自行承担使用本脚本所带来的法律和合规风险，请遵守所在地区的法律法规及各服务平台的使用条款。

---

## 📄 License

[MIT License](LICENSE) © 2024
