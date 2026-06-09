#!/bin/bash
# 测试 TUN 配置是否正确绑定了物理接口

echo "=== TUN 配置诊断 ==="
echo ""

# 1. 检查默认路由
echo "1. 默认路由："
route -n get default 2>/dev/null | grep -E "interface:|gateway:"
echo ""

# 2. 检查物理接口状态
echo "2. 物理接口 en5 状态："
ifconfig en5 2>/dev/null | grep -E "status:|inet "
echo ""

# 3. 检查 TUN daemon 配置
echo "3. TUN daemon 配置检查："
if [ -f "/Library/Application Support/TungBox/tun-daemon.json" ]; then
    echo "   route.default_interface:"
    sudo cat "/Library/Application Support/TungBox/tun-daemon.json" 2>/dev/null | \
        python3 -c "import sys, json; d=json.load(sys.stdin); print('    ', d.get('route', {}).get('default_interface', 'NOT SET'))" 2>/dev/null

    echo "   真实节点 outbound 的 bind_interface:"
    sudo cat "/Library/Application Support/TungBox/tun-daemon.json" 2>/dev/null | \
        python3 -c "import sys, json; d=json.load(sys.stdin); outbounds=d.get('outbounds', []); virtual={'selector','urltest','url-test','direct','block','dns'}; real=[o for o in outbounds if o.get('type','').lower() not in virtual]; print('     前3个:', [(o.get('tag'), o.get('bind_interface', 'NOT SET')) for o in real[:3]])" 2>/dev/null

    echo "   DNS 服务器 detour:"
    sudo cat "/Library/Application Support/TungBox/tun-daemon.json" 2>/dev/null | \
        python3 -c "import sys, json; d=json.load(sys.stdin); servers=d.get('dns', {}).get('servers', []); print('    ', [(s.get('tag'), s.get('detour', 'NOT SET')) for s in servers[:3]])" 2>/dev/null
else
    echo "   配置文件不存在（TUN 未启动过）"
fi
echo ""

# 4. 检查 TUN 接口
echo "4. TUN 接口状态："
utun_list=$(ifconfig -l | tr ' ' '\n' | grep '^utun')
if [ -z "$utun_list" ]; then
    echo "   无 utun 接口"
else
    for iface in $utun_list; do
        if ifconfig "$iface" 2>/dev/null | grep -q "inet 172.19.0.1"; then
            echo "   找到 TungBox TUN 接口: $iface"
            ifconfig "$iface" 2>/dev/null | grep "inet "
        fi
    done
fi
echo ""

# 5. 检查 sing-box 进程
echo "5. sing-box 进程："
ps aux | grep -E "sing-box.*tun-daemon.json" | grep -v grep || echo "   TUN sing-box 未运行"
echo ""

# 6. 检查最近的 TUN 日志
echo "6. 最近的 TUN 服务日志："
if [ -f "/Library/Application Support/TungBox/tun-service.log" ]; then
    grep -E "starting|stopping|refusing|绑定.*出站" "/Library/Application Support/TungBox/tun-service.log" 2>/dev/null | tail -5
else
    echo "   日志文件不存在"
fi
echo ""

echo "=== 诊断完成 ==="
echo ""
echo "期望结果："
echo "  - default_interface 应为 en5 或其他物理接口"
echo "  - 真实节点的 bind_interface 应为 en5"
echo "  - DNS 服务器应有 detour 设置"
echo "  - TUN 接口应存在 172.19.0.1"
