#!/bin/bash

# WARP 一键脚本 - 使用 Cloudflare 官方客户端
# 让 Google 流量自动走 WARP，解锁受限服务

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 显示横幅
show_banner() {
    clear
    echo -e "${CYAN}"
    echo "╔════════════════════════════════════════════════════╗"
    echo "║     🌐 WARP 一键脚本 - Google 自动解锁 🌐           ║"
    echo "║         使用 Cloudflare 官方客户端                  ║"
    echo "╚════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# 检查 root
[[ $EUID -ne 0 ]] && { echo -e "${RED}请使用 root 运行！${NC}"; exit 1; }

# 检测系统
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
    CODENAME=$VERSION_CODENAME
else
    echo -e "${RED}无法检测系统${NC}"; exit 1
fi

ARCH=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
echo -e "${GREEN}系统: $OS $VERSION ($CODENAME) $ARCH${NC}"

# 显示当前 IP
echo -e "\n${YELLOW}当前 IP 信息:${NC}"
CURRENT_IP=$(curl -4 -s --max-time 5 ip.sb)
IP_INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$CURRENT_IP?lang=zh-CN" 2>/dev/null)
echo -e "IP: ${GREEN}$CURRENT_IP${NC}"
echo -e "位置: ${GREEN}$(echo $IP_INFO | grep -oP '"country":"\K[^"]+') - $(echo $IP_INFO | grep -oP '"city":"\K[^"]+')${NC}"

# 安装 Cloudflare WARP 官方客户端
install_warp() {
    echo -e "\n${CYAN}[1/3] 安装 Cloudflare WARP 官方客户端...${NC}"
    
    case $OS in
        ubuntu|debian)
            # 先安装必要依赖
            apt-get update -y >/dev/null 2>&1
            apt-get install -y gnupg curl wget lsb-release >/dev/null 2>&1
            
            # 添加 Cloudflare GPG 密钥
            curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor --output /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
            
            # 添加仓库
            echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $CODENAME main" > /etc/apt/sources.list.d/cloudflare-client.list
            
            # 安装
            apt-get update -y
            apt-get install -y cloudflare-warp
            ;;
        centos|rhel|rocky|almalinux|fedora)
            # 添加仓库
            cat > /etc/yum.repos.d/cloudflare-warp.repo << 'EOF'
[cloudflare-warp]
name=Cloudflare WARP
baseurl=https://pkg.cloudflareclient.com/rpm
enabled=1
gpgcheck=1
gpgkey=https://pkg.cloudflareclient.com/pubkey.gpg
EOF
            if command -v dnf &>/dev/null; then
                dnf install -y cloudflare-warp
            else
                yum install -y cloudflare-warp
            fi
            ;;
        *)
            echo -e "${RED}不支持的系统: $OS${NC}"
            echo -e "${YELLOW}支持的系统: Ubuntu, Debian, CentOS, RHEL, Rocky, AlmaLinux, Fedora${NC}"
            exit 1
            ;;
    esac
    
    if ! command -v warp-cli &>/dev/null; then
        echo -e "${RED}WARP 安装失败${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ WARP 客户端已安装${NC}"
}

# 配置 WARP
configure_warp() {
    echo -e "\n${CYAN}[2/3] 配置 WARP...${NC}"
    
    # 注册设备
    echo -e "正在注册设备..."
    warp-cli --accept-tos registration new 2>/dev/null || warp-cli --accept-tos register 2>/dev/null || true
    
    # 设置为代理模式 (不会接管全部流量，只通过 SOCKS5 代理)
    warp-cli --accept-tos mode proxy 2>/dev/null || warp-cli mode proxy 2>/dev/null || true
    
    # 设置代理端口
    warp-cli --accept-tos proxy port 40000 2>/dev/null || warp-cli proxy port 40000 2>/dev/null || true
    
    # 连接
    echo -e "正在连接 WARP..."
    warp-cli --accept-tos connect 2>/dev/null || warp-cli connect 2>/dev/null
    
    sleep 3
    
    # 显示状态
    STATUS=$(warp-cli --accept-tos status 2>/dev/null || warp-cli status 2>/dev/null)
    echo -e "状态: ${GREEN}$STATUS${NC}"
    
    echo -e "${GREEN}✓ WARP 配置完成${NC}"
}

# 配置透明代理 (让 Google 流量自动走 WARP)
setup_transparent_proxy() {
    echo -e "\n${CYAN}[3/3] 配置透明代理规则...${NC}"
    
    # 禁用 IPv6 访问 Google（避免 IPv4/IPv6 不匹配导致被检测）
    echo -e "配置 IPv6 规则..."
    
    # 方法1: 添加 IPv6 黑洞路由到 Google IPv6 地址
    # Google IPv6 范围: 2607:f8b0::/32
    ip -6 route add blackhole 2607:f8b0::/32 2>/dev/null || true
    
    # 方法2: 设置系统优先使用 IPv4
    if ! grep -q "precedence ::ffff:0:0/96  100" /etc/gai.conf 2>/dev/null; then
        echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf
    fi
    
    # 安装 redsocks (透明代理工具)
    case $OS in
        ubuntu|debian)
            apt-get install -y redsocks iptables >/dev/null 2>&1
            ;;
        centos|rhel|rocky|almalinux|fedora)
            if command -v dnf &>/dev/null; then
                dnf install -y redsocks iptables >/dev/null 2>&1
            else
                yum install -y redsocks iptables >/dev/null 2>&1
            fi
            ;;
    esac
    
    # 创建 redsocks 配置
    cat > /etc/redsocks.conf << 'EOF'
base {
    log_debug = off;
    log_info = on;
    log = "syslog:daemon";
    daemon = on;
    redirector = iptables;
}

redsocks {
    local_ip = 127.0.0.1;
    local_port = 12345;
    ip = 127.0.0.1;
    port = 40000;
    type = socks5;
}
EOF

    # 创建 iptables 规则脚本
    cat > /usr/local/bin/warp-google << 'SCRIPT'
#!/bin/bash

# Service IP definitions (add or modify as needed)
declare -A SERVICE_IPS
SERVICE_IPS[google]="
8.8.4.0/24
8.8.8.0/24
34.0.0.0/9
35.184.0.0/13
35.192.0.0/12
35.224.0.0/12
35.240.0.0/13
64.233.160.0/19
66.102.0.0/20
66.249.64.0/19
72.14.192.0/18
74.125.0.0/16
104.132.0.0/14
108.177.0.0/17
142.250.0.0/15
172.217.0.0/16
172.253.0.0/16
173.194.0.0/16
209.85.128.0/17
216.58.192.0/19
216.239.32.0/19
"
# ChatGPT / OpenAI (AS401518) - 来源: RIPE NCC BGP, 2026-07-19
# OpenAI 自有 IP 段极少，主要通过 Cloudflare(AS13335) 提供 chat.openai.com 服务
# 建议同时覆盖 Cloudflare 的部分 IP 以确保解锁效果
SERVICE_IPS[chatgpt]="
199.47.142.0/23
104.16.0.0/13
104.24.0.0/14
"

# Netflix (AS2906) - 来源: RIPE NCC BGP, 2026-07-19
# 以下为聚合主干段，覆盖 Netflix 全球 CDN 核心 IP
SERVICE_IPS[netflix]="
23.246.0.0/18
37.77.184.0/21
45.57.0.0/17
64.120.128.0/17
66.197.128.0/17
69.53.224.0/19
108.175.32.0/20
185.2.220.0/22
185.9.188.0/22
192.173.64.0/18
198.38.96.0/19
198.45.48.0/20
207.45.72.0/22
208.75.76.0/22
"

# 动态从 RIPE NCC API 更新指定 ASN 的 IPv4 前缀
update_asn_ips() {
    local svc="$1"
    local asn="$2"
    echo "正在从 RIPE NCC 更新 $svc (AS$asn) 的 IP 列表..."
    local result
    result=$(curl -sf --max-time 15 "https://stat.ripe.net/data/announced-prefixes/data.json?resource=AS${asn}" 2>/dev/null)
    if [ -z "$result" ]; then
        echo "  警告: 无法获取 AS$asn 数据，使用内置 IP 列表"
        return
    fi
    # 提取 IPv4 前缀（过滤 IPv6）
    local ipv4list
    ipv4list=$(echo "$result" | tr ',' '\n' | grep -oP '"prefix":"\K[0-9][^"]+' | grep -v ':')
    if [ -n "$ipv4list" ]; then
        SERVICE_IPS[$svc]="$ipv4list"
        local count
        count=$(echo "$ipv4list" | wc -l)
        echo "  已更新 $svc: 共 $count 个 IPv4 前缀"
    else
        echo "  警告: 未解析到 IPv4 前缀，使用内置 IP 列表"
    fi
}

start() {
    echo "启动多服务透明代理..."

    # 动态更新 IP（可选，需要 curl 和网络访问）
    if command -v curl &>/dev/null; then
        update_asn_ips google  15169   # Google LLC (主 ASN)
        update_asn_ips netflix 2906
        update_asn_ips chatgpt 401518
    fi

    # 启动 redsocks
    pkill redsocks 2>/dev/null || true
    redsocks -c /etc/redsocks.conf

    # 为每个服务创建 iptables 链并添加规则
    for svc in "${!SERVICE_IPS[@]}"; do
        chain="WARP_${svc^^}"
        iptables -t nat -N "$chain" 2>/dev/null || iptables -t nat -F "$chain"
        iplist=${SERVICE_IPS[$svc]}
        local count=0
        for ip in $iplist; do
            iptables -t nat -A "$chain" -d $ip -p tcp -j REDIRECT --to-ports 12345
            ((count++))
        done
        iptables -t nat -C OUTPUT -j "$chain" 2>/dev/null || iptables -t nat -A OUTPUT -j "$chain"
        echo "  $svc: 已添加 $count 条规则"
    done
    echo "多服务透明代理已启动"
}

stop() {
    echo "停止多服务透明代理..."
    pkill redsocks 2>/dev/null || true
    for svc in "${!SERVICE_IPS[@]}"; do
        chain="WARP_${svc^^}"
        iptables -t nat -D OUTPUT -j "$chain" 2>/dev/null
        iptables -t nat -F "$chain" 2>/dev/null
        iptables -t nat -X "$chain" 2>/dev/null
    done
    echo "多服务透明代理已停止"
}

status() {
    echo "=== WARP 状态 ==="
    warp-cli status 2>/dev/null || echo "WARP 未运行"
    echo ""
    echo "=== Redsocks 状态 ==="
    pgrep -x redsocks >/dev/null && echo "运行中" || echo "未运行"
    echo ""
    echo "=== iptables 规则 ==="
    for svc in "${!SERVICE_IPS[@]}"; do
        chain="WARP_${svc^^}"
        echo "--- $svc ---"
        iptables -t nat -L "$chain" -n 2>/dev/null | head -5 || echo "无规则"
    done
}

case "$1" in
    start) start ;;
    stop) stop ;;
    restart) stop; sleep 1; start ;;
    status) status ;;
    *) echo "用法: $0 {start|stop|restart|status}" ;;
esac
SCRIPT

    chmod +x /usr/local/bin/warp-google
    
    # 启动透明代理
    /usr/local/bin/warp-google start
    
    # 创建 systemd 服务
    cat > /etc/systemd/system/warp-google.service << 'EOF'
[Unit]
Description=WARP Google Transparent Proxy
After=network.target warp-svc.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/warp-google start
ExecStop=/usr/local/bin/warp-google stop

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable warp-google 2>/dev/null

    # 创建每 7 天自动重启的 systemd timer（用于定期刷新 BGP IP 列表）
    cat > /etc/systemd/system/warp-google-update.service << 'EOF'
[Unit]
Description=WARP Transparent Proxy Weekly IP Update
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/warp-google restart
EOF

    cat > /etc/systemd/system/warp-google-update.timer << 'EOF'
[Unit]
Description=WARP IP List Weekly Auto-Update

[Timer]
OnBootSec=10min
OnUnitActiveSec=7d
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now warp-google-update.timer 2>/dev/null
    echo -e "${GREEN}✓ 已启用每 7 天自动更新 IP 列表的定时任务${NC}"
    echo -e "${GREEN}✓ 透明代理配置完成${NC}"
}

# 兼容旧版函数名，避免不同版本脚本调用不一致
if ! declare -F setup_transparent_proxy >/dev/null && declare -F setup_transparent_proxy_google >/dev/null; then
    setup_transparent_proxy() { setup_transparent_proxy_google "$@"; }
fi
if ! declare -F setup_transparent_proxy_google >/dev/null && declare -F setup_transparent_proxy >/dev/null; then
    setup_transparent_proxy_google() { setup_transparent_proxy "$@"; }
fi

# 测试连接
test_connection() {
    echo -e "\n${CYAN}测试连接...${NC}"
    
    sleep 2
    
    # 测试 Google
    GOOGLE_TEST=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
    if [ "$GOOGLE_TEST" = "200" ]; then
        echo -e "${GREEN}✓ Google 连接成功！${NC}"
    else
        echo -e "${YELLOW}Google 测试返回: $GOOGLE_TEST${NC}"
    fi
    
    # 显示 WARP IP
    WARP_IP=$(curl -x socks5://127.0.0.1:40000 -s --max-time 10 ip.sb 2>/dev/null)
    if [ -n "$WARP_IP" ]; then
        WARP_INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$WARP_IP?lang=zh-CN" 2>/dev/null)
        echo -e "\nWARP IP: ${GREEN}$WARP_IP${NC}"
        echo -e "WARP 位置: ${GREEN}$(echo $WARP_INFO | grep -oP '"country":"\K[^"]+') - $(echo $WARP_INFO | grep -oP '"city":"\K[^"]+')${NC}"
    fi
}

# 创建管理脚本
create_management() {
    cat > /usr/local/bin/warp << 'EOF'
#!/bin/bash
case "$1" in
    status)
        warp-cli status 2>/dev/null
        echo ""
        /usr/local/bin/warp-google status 2>/dev/null
        ;;
    start)
        warp-cli connect 2>/dev/null
        /usr/local/bin/warp-google start
        ;;
    stop)
        /usr/local/bin/warp-google stop
        warp-cli disconnect 2>/dev/null
        ;;
    restart)
        $0 stop
        sleep 2
        $0 start
        ;;
    test)
        echo "测试 Google 连接..."
        curl -s --max-time 10 -o /dev/null -w "状态码: %{http_code}\n" https://www.google.com
        ;;
    ip)
        echo "直连 IP:"
        curl -4 -s ip.sb
        echo ""
        echo "WARP IP:"
        curl -x socks5://127.0.0.1:40000 -s ip.sb
        echo ""
        ;;
    uninstall)
        echo "正在卸载..."
        /usr/local/bin/warp-google stop 2>/dev/null
        warp-cli disconnect 2>/dev/null
        systemctl disable warp-google 2>/dev/null
        rm -f /etc/systemd/system/warp-google.service
        rm -f /usr/local/bin/warp-google
        rm -f /usr/local/bin/warp
        rm -f /etc/redsocks.conf
        apt-get remove -y cloudflare-warp redsocks 2>/dev/null || yum remove -y cloudflare-warp redsocks 2>/dev/null
        echo "WARP 已卸载"
        ;;
    *)
        echo "WARP 管理工具"
        echo ""
        echo "用法: warp <命令>"
        echo ""
        echo "命令:"
        echo "  status    查看状态"
        echo "  start     启动 WARP"
        echo "  stop      停止 WARP"
        echo "  restart   重启 WARP"
        echo "  test      测试 Google"
        echo "  ip        查看 IP"
        echo "  uninstall 卸载 WARP"
        ;;
esac
EOF
    chmod +x /usr/local/bin/warp
}

# 安装主流程
do_install() {
    install_warp
    configure_warp
    setup_transparent_proxy
    create_management
    test_connection

    echo -e "\n${GREEN}╔════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║          🎉 安装完成！多服务已解锁 🎉               ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════╝${NC}"
    echo -e "\n${YELLOW}所有 Google / Netflix / ChatGPT 流量现已自动通过 WARP！${NC}"
    echo -e "${YELLOW}IP 列表每 7 天自动从 BGP 数据库刷新，无需手动维护。${NC}\n"

    # 开机自启状态检查
    echo -e "${CYAN}══════ 开机自启状态 ══════${NC}"
    if systemctl is-enabled warp-google &>/dev/null; then
        echo -e "  warp-google.service    : ${GREEN}✓ 已开机自启${NC}"
    else
        echo -e "  warp-google.service    : ${RED}✗ 未开机自启${NC}（运行 systemctl enable warp-google 修复）"
    fi
    if systemctl is-enabled warp-svc &>/dev/null; then
        echo -e "  warp-svc.service       : ${GREEN}✓ 已开机自启${NC}"
    else
        echo -e "  warp-svc.service       : ${YELLOW}⚠ 未检测到（可能需要手动启用）${NC}"
    fi
    if systemctl is-enabled warp-google-update.timer &>/dev/null; then
        echo -e "  warp-google-update.timer: ${GREEN}✓ 每 7 天自动更新 IP${NC}"
    else
        echo -e "  warp-google-update.timer: ${RED}✗ 定时更新未启用${NC}"
    fi

    echo -e "\n${CYAN}管理命令: warp {status|start|stop|restart|test|ip|update|uninstall}${NC}\n"
}

# 卸载
do_uninstall() {
    echo -e "\n${YELLOW}正在卸载 WARP...${NC}"
    /usr/local/bin/warp-google stop 2>/dev/null
    warp-cli disconnect 2>/dev/null
    systemctl disable --now warp-google 2>/dev/null
    systemctl disable --now warp-google-update.timer 2>/dev/null
    systemctl stop warp-svc 2>/dev/null
    rm -f /etc/systemd/system/warp-google.service
    rm -f /etc/systemd/system/warp-google-update.service
    rm -f /etc/systemd/system/warp-google-update.timer
    rm -f /usr/local/bin/warp-google
    rm -f /usr/local/bin/warp
    rm -f /etc/redsocks.conf
    systemctl daemon-reload

    # 清理所有 iptables 链（兼容多服务命名）
    for chain in WARP_GOOGLE WARP_NETFLIX WARP_CHATGPT; do
        iptables -t nat -D OUTPUT -j "$chain" 2>/dev/null
        iptables -t nat -F "$chain" 2>/dev/null
        iptables -t nat -X "$chain" 2>/dev/null
    done

    # 删除 IPv6 黑洞路由
    ip -6 route del blackhole 2607:f8b0::/32 2>/dev/null

    # 卸载软件包
    case $OS in
        ubuntu|debian)
            apt-get remove -y cloudflare-warp redsocks 2>/dev/null
            rm -f /etc/apt/sources.list.d/cloudflare-client.list
            ;;
        centos|rhel|rocky|almalinux|fedora)
            yum remove -y cloudflare-warp redsocks 2>/dev/null || dnf remove -y cloudflare-warp redsocks 2>/dev/null
            rm -f /etc/yum.repos.d/cloudflare-warp.repo
            ;;
    esac

    echo -e "${GREEN}✓ WARP 已完全卸载${NC}\n"
}

# 查看状态
do_status() {
    echo -e "\n${CYAN}══════════════ WARP 运行状态 ══════════════${NC}\n"
    
    # WARP 客户端状态
    echo -e "${YELLOW}【WARP 客户端】${NC}"
    if command -v warp-cli &>/dev/null; then
        warp-cli status 2>/dev/null || echo "未运行"
    else
        echo -e "${RED}未安装${NC}"
    fi
    
    echo ""
    
    # Redsocks 状态
    echo -e "${YELLOW}【透明代理】${NC}"
    if pgrep -x redsocks >/dev/null; then
        echo -e "${GREEN}运行中${NC}"
    else
        echo -e "${RED}未运行${NC}"
    fi
    
    echo ""
    
    # iptables 规则
    echo -e "${YELLOW}【iptables 规则】${NC}"
    iptables -t nat -L WARP_GOOGLE -n 2>/dev/null | head -3 || echo -e "${RED}无规则${NC}"
    
    echo -e "\n${CYAN}════════════════════════════════════════════${NC}\n"
}

# 查看 IP
do_show_ip() {
    echo -e "\n${CYAN}══════════════ IP 信息 ══════════════${NC}\n"
    
    echo -e "${YELLOW}【直连 IP】${NC}"
    DIRECT_IP=$(curl -4 -s --max-time 5 ip.sb)
    DIRECT_INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$DIRECT_IP?lang=zh-CN" 2>/dev/null)
    echo -e "IP: ${GREEN}$DIRECT_IP${NC}"
    echo -e "位置: $(echo $DIRECT_INFO | grep -oP '"country":"\K[^"]+') - $(echo $DIRECT_INFO | grep -oP '"city":"\K[^"]+')\n"
    
    echo -e "${YELLOW}【WARP IP】${NC}"
    WARP_IP=$(curl -x socks5://127.0.0.1:40000 -s --max-time 5 ip.sb 2>/dev/null)
    if [ -n "$WARP_IP" ]; then
        WARP_INFO=$(curl -s --max-time 5 "http://ip-api.com/json/$WARP_IP?lang=zh-CN" 2>/dev/null)
        echo -e "IP: ${GREEN}$WARP_IP${NC}"
        echo -e "位置: $(echo $WARP_INFO | grep -oP '"country":"\K[^"]+') - $(echo $WARP_INFO | grep -oP '"city":"\K[^"]+')\n"
    else
        echo -e "${RED}无法获取 (WARP 可能未运行)${NC}\n"
    fi
    
    echo -e "${CYAN}══════════════════════════════════════${NC}\n"
}

# 测试 Google 连接
do_test_google() {
    echo -e "\n${CYAN}测试 Google 连接...${NC}"
    RESULT=$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" https://www.google.com)
    if [ "$RESULT" = "200" ]; then
        echo -e "${GREEN}✓ Google 连接成功！状态码: $RESULT${NC}\n"
    else
        echo -e "${RED}✗ Google 连接失败，状态码: $RESULT${NC}\n"
    fi
}

# 启动服务
do_start() {
    echo -e "\n${CYAN}启动 WARP 服务...${NC}"
    warp-cli connect 2>/dev/null
    /usr/local/bin/warp-google start 2>/dev/null
    echo -e "${GREEN}✓ WARP 已启动${NC}\n"
}

# 停止服务
do_stop() {
    echo -e "\n${CYAN}停止 WARP 服务...${NC}"
    /usr/local/bin/warp-google stop 2>/dev/null
    warp-cli disconnect 2>/dev/null
    echo -e "${GREEN}✓ WARP 已停止${NC}\n"
}

# 显示菜单
show_menu() {
    local choice=""

    # 如果传入了命令行参数，直接使用；否则进入交互模式
    if [[ -n "$1" ]]; then
        choice="$1"
    else
        echo -e "${YELLOW}请选择操作:${NC}\n"
        echo -e "  ${GREEN}1.${NC} 安装 WARP (解锁 Gemini和商店等)"
        echo -e "  ${GREEN}2.${NC} 卸载 WARP"
        echo -e "  ${GREEN}3.${NC} 查看状态"
        echo -e "  ${GREEN}0.${NC} 退出\n"
        read -p "请输入选项 [0-3]: " choice
    fi

    case $choice in
        1) do_install ;;
        2) do_uninstall ;;
        3) do_status; do_show_ip; do_test_google ;;
        0) echo -e "\n${GREEN}再见！${NC}\n"; exit 0 ;;
        *)
            echo -e "\n${RED}无效选项: '$choice'${NC}\n"
            # 如果是通过命令行参数传入的无效值，直接退出并返回错误码
            if [[ -n "$1" ]]; then
                exit 1
            fi
            ;;
    esac
}

# 主入口
main() {
    show_banner
    
    # 检查 root
    [[ $EUID -ne 0 ]] && { echo -e "${RED}请使用 root 运行！${NC}"; exit 1; }
    
    # 检测系统
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
        CODENAME=$VERSION_CODENAME
    else
        echo -e "${RED}无法检测系统${NC}"; exit 1
    fi
    
    ARCH=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
    echo -e "${GREEN}系统: $OS $VERSION ($CODENAME) $ARCH${NC}\n"
    
    show_menu "$@"
}

main "$@"
