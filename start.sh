#!/bin/sh

# 定义常量
MIHOMO_PATH="$(dirname "$0")"
LOG_FILE="${MIHOMO_PATH}/run.logs"
PID_FILE="${MIHOMO_PATH}/mihomo.pid"

# 确保目录存在
if [ ! -d "$MIHOMO_PATH" ]; then
    echo "错误: mihomo 目录不存在!"
    exit 1
fi

# 停止旧的 mihomo 进程
echo "正在停止旧的 mihomo 进程..."
if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") >/dev/null 2>&1; then
    kill $(cat "$PID_FILE")
    sleep 1
    if kill -0 $(cat "$PID_FILE") >/dev/null 2>&1; then
        echo "警告: 无法正常结束 mihomo 进程，强制终止..."
        kill -9 $(cat "$PID_FILE")
    fi
    rm -f "$PID_FILE"
else
    pkill mihomo
    sleep 1
    if pgrep mihomo > /dev/null; then
        echo "警告: 无法正常结束 mihomo 进程，强制终止..."
        pkill -9 mihomo
    fi
fi

# 启动 mihomo
echo "正在启动 mihomo..."
${MIHOMO_PATH}/mihomo -d ${MIHOMO_PATH} > ${LOG_FILE} 2>&1 &
MIHOMO_PID=$!
echo $MIHOMO_PID > "$PID_FILE"

# 检查 mihomo 是否成功启动
sleep 2
if ! kill -0 $MIHOMO_PID >/dev/null 2>&1; then
    echo "错误: mihomo 启动失败!"
    rm -f "$PID_FILE"
    exit 1
fi
echo "mihomo 启动成功! (PID: $MIHOMO_PID)"

# 配置 IP 转发
echo "正在配置网络转发规则..."
echo 1 > /proc/sys/net/ipv4/ip_forward

# 验证 IP 转发是否开启
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
    echo "错误: IP 转发配置失败!"
    exit 1
fi
echo "IP 转发已开启"

# 配置 RP 过滤器
echo 2 > /proc/sys/net/ipv4/conf/default/rp_filter
echo 2 > /proc/sys/net/ipv4/conf/all/rp_filter

# 验证 RP 过滤器设置
if [ "$(cat /proc/sys/net/ipv4/conf/default/rp_filter)" != "2" ] || [ "$(cat /proc/sys/net/ipv4/conf/all/rp_filter)" != "2" ]; then
    echo "警告: RP 过滤器配置可能有问题!"
fi

# 清空并设置 iptables 规则
echo "正在清空 iptables 规则..."
iptables -F

# 开启热点转发
echo "正在配置热点转发..."
# 允许从 ice 接口进入的流量转发
iptables -A FORWARD -i ice -j ACCEPT
    
# 允许转发到 ice 接口的流量
iptables -A FORWARD -o ice -j ACCEPT

# 验证 iptables 规则
echo "正在验证转发规则..."
FORWARD_RULES=$(iptables -L FORWARD -n | wc -l)
if [ "$FORWARD_RULES" -le 3 ]; then
    echo "警告: 转发规则可能未正确设置!"
else
    echo "转发规则已正确配置"
fi

echo "所有配置完成!"
echo "查看日志: cat $LOG_FILE"
echo "停止服务: kill $(cat $PID_FILE)"