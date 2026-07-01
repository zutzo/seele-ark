#!/bin/sh

# 定义常量
MIHOMO_PATH="$(dirname "$0")"
MIHOMO_EXECUTABLE="${MIHOMO_PATH}/mihomo" # 定义 mihomo 可执行文件路径
LOG_FILE="${MIHOMO_PATH}/run.logs"
PID_FILE="${MIHOMO_PATH}/mihomo.pid"

# --- 权限检查 ---
# 1. 检查脚本是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
  echo "错误: 此脚本需要以 root 权限运行!"
  echo "请尝试使用 root 用权限后执行。"
  exit 1
fi
echo "脚本以 root 权限运行。"

# --- 文件和目录检查 ---
# 2. 确保 mihomo 目录存在
if [ ! -d "$MIHOMO_PATH" ]; then
    echo "错误: mihomo 目录不存在! 路径: $MIHOMO_PATH"
    exit 1
fi

# 3. 检查 mihomo 可执行文件是否存在
if [ ! -f "$MIHOMO_EXECUTABLE" ]; then
    echo "错误: mihomo 可执行文件不存在! 路径: $MIHOMO_EXECUTABLE"
    exit 1
fi

# 4. 检查 mihomo 是否有执行权限，如果没有则尝试添加
if [ ! -x "$MIHOMO_EXECUTABLE" ]; then
    echo "信息: 检测到 mihomo 文件没有执行权限，正在尝试添加..."
    chmod +x "$MIHOMO_EXECUTABLE"
    # 检查 chmod 是否成功
    if [ $? -ne 0 ]; then
        echo "错误: 无法为 $MIHOMO_EXECUTABLE 添加执行权限!"
        echo "请检查文件系统权限或文件所有者。"
        exit 1
    else
        echo "成功为 $MIHOMO_EXECUTABLE 添加了执行权限。"
    fi
else
    echo "信息: mihomo 文件已具有执行权限。"
fi

# --- 进程管理 ---
# 停止旧的 mihomo 进程
echo "正在停止旧的 mihomo 进程..."
if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") >/dev/null 2>&1; then
    echo "通过 PID 文件停止进程: $(cat $PID_FILE)"
    kill $(cat "$PID_FILE")
    sleep 1
    # 再次检查是否成功停止
    if kill -0 $(cat "$PID_FILE") >/dev/null 2>&1; then
        echo "警告: 无法正常结束 mihomo 进程 $(cat $PID_FILE)，强制终止..."
        kill -9 $(cat "$PID_FILE")
    else
        echo "进程 $(cat $PID_FILE) 已停止。"
    fi
    rm -f "$PID_FILE"
else
    # 如果 PID 文件不存在或进程已死，尝试通过名称查找并杀死
    if pgrep -f "${MIHOMO_EXECUTABLE}" > /dev/null; then # 使用更精确的 pgrep
        echo "通过进程名停止 mihomo..."
        pkill -9 -f "${MIHOMO_EXECUTABLE}" # 强制终止以确保清理
        sleep 1
        if pgrep -f "${MIHOMO_EXECUTABLE}" > /dev/null; then
             echo "警告: 强制终止 mihomo 进程似乎失败了。"
        else
             echo "通过进程名停止 mihomo 成功。"
        fi
    else
        echo "没有找到正在运行的 mihomo 进程 (无论是通过 PID 文件还是进程名)。"
    fi
    # 确保 PID 文件被移除（即使之前不存在或无效）
    rm -f "$PID_FILE"
fi

# --- 启动 mihomo ---
echo "正在启动 mihomo..."
# 使用 nohup 确保即使终端关闭，进程也能继续运行（可选，但推荐）
# nohup ${MIHOMO_EXECUTABLE} -d ${MIHOMO_PATH} > ${LOG_FILE} 2>&1 &
# 或者保持原来的方式：
${MIHOMO_EXECUTABLE} -d ${MIHOMO_PATH} > ${LOG_FILE} 2>&1 &
MIHOMO_PID=$!

# 检查 $! 是否为空或非数字 (启动失败的迹象)
if [ -z "$MIHOMO_PID" ] || ! [ "$MIHOMO_PID" -eq "$MIHOMO_PID" ] 2>/dev/null; then
    echo "错误: mihomo 启动失败! 未能获取有效的 PID。"
    echo "请检查日志文件: $LOG_FILE"
    rm -f "$PID_FILE" # 确保不留下无效的 PID 文件
    exit 1
fi

# 将 PID 写入文件
echo $MIHOMO_PID > "$PID_FILE"
echo "mihomo 进程尝试启动，PID: $MIHOMO_PID"

# 检查 mihomo 是否成功启动 (更可靠的方式是检查进程是否存在)
sleep 2 # 等待一段时间让进程稳定
if ! kill -0 $MIHOMO_PID >/dev/null 2>&1; then
    echo "错误: mihomo 启动后似乎立即退出了!"
    echo "请检查日志文件: $LOG_FILE"
    cat "$LOG_FILE" # 输出日志内容帮助诊断
    rm -f "$PID_FILE"
    exit 1
fi
echo "mihomo 启动成功确认! (PID: $MIHOMO_PID)"

# --- 网络配置 (已确认有 root 权限) ---
echo "正在配置网络转发规则..."

# 尝试配置 IP 转发
echo 1 > /proc/sys/net/ipv4/ip_forward
if [ $? -ne 0 ]; then
    echo "错误: 配置 IP 转发失败 (写入 /proc/sys/net/ipv4/ip_forward)。"
    # 考虑是否停止 mihomo
    # kill $MIHOMO_PID; rm -f "$PID_FILE"; exit 1
fi
# 验证 IP 转发是否开启
if [ "$(cat /proc/sys/net/ipv4/ip_forward)" != "1" ]; then
    echo "错误: IP 转发状态验证失败!"
    # 考虑是否停止 mihomo
    # kill $MIHOMO_PID; rm -f "$PID_FILE"; exit 1
else
    echo "IP 转发已开启。"
fi

# 配置 RP 过滤器
echo "正在配置 RP 过滤器..."
echo 2 > /proc/sys/net/ipv4/conf/default/rp_filter
echo 2 > /proc/sys/net/ipv4/conf/all/rp_filter
# 验证 RP 过滤器设置
if [ "$(cat /proc/sys/net/ipv4/conf/default/rp_filter)" != "2" ] || [ "$(cat /proc/sys/net/ipv4/conf/all/rp_filter)" != "2" ]; then
    echo "警告: RP 过滤器配置验证未通过!"
else
    echo "RP 过滤器已配置。"
fi

# 清空并设置 iptables 规则
echo "正在清空 iptables FORWARD 链规则..."
iptables -F FORWARD
if [ $? -ne 0 ]; then
    echo "错误: 清空 iptables FORWARD 链失败。"
    # 考虑是否停止 mihomo
    # kill $MIHOMO_PID; rm -f "$PID_FILE"; exit 1
fi

# 开启热点转发 (假设热点接口名为 'ice')
echo "正在配置热点转发 (接口: ice)..."
iptables -A FORWARD -i ice -j ACCEPT
iptables -A FORWARD -o ice -j ACCEPT

# 验证 iptables 规则
echo "正在验证转发规则..."
FORWARD_RULES_COUNT=$(iptables -L FORWARD -n --line-numbers | grep -c "ice")
if [ "$FORWARD_RULES_COUNT" -lt 2 ]; then
    echo "警告: 针对接口 'ice' 的转发规则可能未正确设置! (预期至少 2 条，实际 $FORWARD_RULES_COUNT 条)"
    echo "当前 FORWARD 链规则:"
    iptables -L FORWARD -n -v
else
    echo "针对接口 'ice' 的转发规则已配置。"
fi

echo "--- 所有配置完成! ---"
echo "mihomo 正在后台运行 (PID: $(cat $PID_FILE))"
echo "日志文件: $LOG_FILE (使用 'tail -f $LOG_FILE' 实时查看)"
echo "停止服务: kill $(cat $PID_FILE) 或执行 sh $0 stop (如果启用了停止功能)"

exit 0 
