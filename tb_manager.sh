cat > tb_manager.sh << 'EOF'
#!/bin/bash
#
# tb_manager.sh - v4.8 (No Flicker & Silent Mode)
#

CONF_FILE="./traffic_balancer.conf"
PID_FILE="/tmp/traffic_balancer.pid"
LOG_FILE="./traffic_balancer.log"
STATUS_FILE="/tmp/tb_status"

# 颜色定义
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"
PURPLE="\033[35m"
PLAIN="\033[0m"

# ================= 资源配置 =================
UA_LIST=(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/119.0.0.0 Safari/537.36"
)
DOWNLOAD_URLS=(
    "https://speed.cloudflare.com/__down?bytes=50000000"
    "http://speedtest.tele2.net/1GB.zip"
    "http://speedtest.sfo2.digitalocean.com/1gb.test"
)

# ================= 1. 配置文件 (默认比例100/限速7000) =================
create_default_config() {
    if [[ ! -f "$CONF_FILE" ]]; then
        cat > "$CONF_FILE" << CONFIG_EOF
TARGET_RATIO=100
RATIO_TOLERANCE=0.3
MIN_SPEED_KB=100
MAX_SPEED_KB=7000
NETWORK_INTERFACE=""
DAILY_MIN_GB=1
DAILY_MAX_GB=5
RUN_MODE="normal"
CONFIG_EOF
    fi
}

# ================= 2. 后台核心逻辑 =================
run_daemon() {
    source "$CONF_FILE"
    # 强制重置状态文件，避免旧数据干扰
    echo "" > "$STATUS_FILE"
    
    daemon_log() { echo "[$(date '+%F %T')] $*" >> "$LOG_FILE"; }
    detect_interface() {
        if [[ -n "$NETWORK_INTERFACE" ]]; then echo "$NETWORK_INTERFACE"; return; fi
        ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -1
    }
    
    IFACE=$(detect_interface)
    if [[ -z "$IFACE" ]]; then daemon_log "错误: 无法检测网卡"; exit 1; fi
    
    TODAY_LIMIT_GB=$((DAILY_MIN_GB + RANDOM % (DAILY_MAX_GB - DAILY_MIN_GB + 1)))
    daemon_log "启动 v4.8 | 接口: $IFACE | 目标: $TARGET_RATIO | 限速: $MAX_SPEED_KB"

    get_bytes() { grep "$IFACE:" /proc/net/dev | awk '{print $2, $10}'; }
    read -r PREV_RX PREV_TX <<< "$(get_bytes)"
    PREV_TIME=$(date +%s)
    CURL_PID=""
    IS_PAUSED=false
    TODAY_BYTES=0
    CURRENT_DAY=$(date +%d)

    cleanup_exit() {
        if [[ -n "$CURL_PID" ]]; then kill -9 "$CURL_PID" 2>/dev/null; fi
        rm -f "$PID_FILE" "$STATUS_FILE"; exit 0
    }
    trap cleanup_exit SIGTERM SIGINT SIGQUIT SIGHUP

    while true; do
        # 随机模式逻辑
        if [[ "$RUN_MODE" == "random" && "$IS_PAUSED" == "false" && -z "$CURL_PID" ]]; then
             if [ $((RANDOM % 10)) -lt 3 ]; then sleep $((10 + RANDOM % 50)); fi
        fi
        sleep 3
        
        # 跨天重置
        NOW_DAY=$(date +%d)
        if [[ "$NOW_DAY" != "$CURRENT_DAY" ]]; then
            CURRENT_DAY=$NOW_DAY; TODAY_BYTES=0
            TODAY_LIMIT_GB=$((DAILY_MIN_GB + RANDOM % (DAILY_MAX_GB - DAILY_MIN_GB + 1)))
        fi

        # 计算速度
        read -r CURR_RX CURR_TX <<< "$(get_bytes)"
        CURR_TIME=$(date +%s); DT=$((CURR_TIME - PREV_TIME)); [ $DT -le 0 ] && continue
        DRX=$((CURR_RX - PREV_RX)); DTX=$((CURR_TX - PREV_TX))
        
        if [[ "$IS_PAUSED" == "false" ]]; then TODAY_BYTES=$((TODAY_BYTES + DRX)); fi
        
        RX_RATE=$(( DRX / DT )); TX_RATE=$(( DTX / DT ))
        if [[ $CURR_TX -gt 0 ]]; then
            CURR_RATIO=$(awk -v r="$CURR_RX" -v t="$CURR_TX" 'BEGIN {printf "%.2f", r/t}')
        else CURR_RATIO=0; fi
        
        LIMIT_BYTES=$((TODAY_LIMIT_GB * 1024 * 1024 * 1024))
        LIMIT_REACHED=$(( TODAY_BYTES >= LIMIT_BYTES ? 1 : 0 ))
        TODAY_GB=$(awk -v b="$TODAY_BYTES" 'BEGIN {printf "%.2f", b/1073741824}')
        
        # === 写入状态 (严格加引号，防止闪烁) ===
        {
            echo "RX_RATE=$RX_RATE"; echo "TX_RATE=$TX_RATE"
            echo "CURR_RATIO=$CURR_RATIO"; echo "TARGET=$TARGET_RATIO"
            echo "TODAY_GB=$TODAY_GB"; echo "LIMIT_GB=$TODAY_LIMIT_GB"
            echo "LIMIT_REACHED=$LIMIT_REACHED"; echo "RUN_MODE=\"$RUN_MODE\""
            echo "MODE_LABEL=\"标准运行\""; echo "UA_LABEL=\"默认\""
        } > "$STATUS_FILE"

        # 暂停/恢复逻辑
        if [[ $LIMIT_REACHED -eq 1 ]]; then
            if [[ "$IS_PAUSED" == "false" ]]; then
                kill "$CURL_PID" 2>/dev/null; CURL_PID=""; IS_PAUSED=true; daemon_log "今日限额达标"
            fi
            PREV_RX=$CURR_RX; PREV_TX=$CURR_TX; PREV_TIME=$CURR_TIME; continue
        fi

        TX_KBPS=$((TX_RATE / 1024))
        TARGET_KBPS=$(awk -v tx="$TX_KBPS" -v r="$TARGET_RATIO" 'BEGIN {print int(tx * r)}')
        UPPER=$(awk -v r="$TARGET_RATIO" 'BEGIN {print r + 0.3}')
        
        # 检查是否超标
        IS_OVER=$(awk -v c="$CURR_RATIO" -v u="$UPPER" 'BEGIN {print (c>u)?1:0}')
        
        if [[ "$IS_OVER" -eq 1 ]]; then
             if [[ "$IS_PAUSED" == "false" ]]; then
                 kill "$CURL_PID" 2>/dev/null; CURL_PID=""; IS_PAUSED=true; daemon_log "暂停: 比例过高"
             fi
        else
             if [[ "$IS_PAUSED" == "true" || -z "$CURL_PID" || ! -d "/proc/$CURL_PID" ]]; then
                 IS_PAUSED=false
                 URL=${DOWNLOAD_URLS[$((RANDOM % ${#DOWNLOAD_URLS[@]}))]}
                 if [[ "$URL" == *"?"* ]]; then URL="${URL}&rand=${RANDOM}"; else URL="${URL}?rand=${RANDOM}"; fi
                 LIMIT_K=$TARGET_KBPS
                 [[ $LIMIT_K -lt $MIN_SPEED_KB ]] && LIMIT_K=$MIN_SPEED_KB
                 [[ $LIMIT_K -gt $MAX_SPEED_KB ]] && LIMIT_K=$MAX_SPEED_KB
                 
                 curl -s -o /dev/null -A "${UA_LIST[$((RANDOM % ${#UA_LIST[@]}))]}" \
                 --limit-rate "${LIMIT_K}k" -L "$URL" &
                 CURL_PID=$!
             fi
        fi
        PREV_RX=$CURR_RX; PREV_TX=$CURR_TX; PREV_TIME=$CURR_TIME
    done
}

# ================= 3. 界面逻辑 (无闪烁修复版) =================
human_speed() {
    local num=$1
    if [ $num -gt 1048576 ]; then awk -v n="$num" 'BEGIN {printf "%.2f MB/s", n/1048576}';
    else awk -v n="$num" 'BEGIN {printf "%.2f KB/s", n/1024}'; fi
}

view_dashboard() {
    # 1. 初始清屏一次
    clear
    # 2. 隐藏光标 (避免光标闪烁)
    echo -ne "\033[?25l"
    
    while true; do
        # 3. 安全读取状态 (屏蔽错误输出)
        if [[ -f "$STATUS_FILE" ]]; then source "$STATUS_FILE" 2>/dev/null; else RX_RATE=0; TX_RATE=0; CURR_RATIO=0; TODAY_GB=0; LIMIT_REACHED=0; LIMIT_GB=0; fi
        
        # 4. 关键：不使用 clear，而是把光标移动到左上角 (0,0) 直接覆盖
        echo -ne "\033[H"
        
        echo -e "${CYAN}========== Traffic Balancer v4.8 ==========${PLAIN}"
        if [[ -f "$PID_FILE" ]] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
            echo -e "  状态: ${GREEN}运行中 (PID: $(cat $PID_FILE))${PLAIN}   "
        else
            echo -e "  状态: ${RED}未运行${PLAIN}                    "
        fi
        
        echo -e "  ⬇️  下载: ${GREEN}$(human_speed ${RX_RATE:-0})${PLAIN}        "
        echo -e "  ⬆️  上传: ${BLUE}$(human_speed ${TX_RATE:-0})${PLAIN}        "
        echo -e "  📊 比例: ${YELLOW}${CURR_RATIO:-0} : 1${PLAIN} (目标 $TARGET_RATIO)    "
        
        if [[ "$LIMIT_REACHED" -eq 1 ]]; then 
            echo -e "  🛑 今日: ${RED}${TODAY_GB} / ${LIMIT_GB} GB (暂停)${PLAIN}      "
        else 
            echo -e "  📅 今日: ${GREEN}${TODAY_GB} / ${LIMIT_GB} GB${PLAIN}           "
        fi
        echo -e "${CYAN}===========================================${PLAIN}"
        echo -e "  按 ${RED}0${PLAIN} 退出监控"
        
        # 5. 清除屏幕剩余部分 (防止残影)
        echo -ne "\033[0J"
        
        # 6. 等待 1 秒
        read -t 1 -n 1 input
        if [[ "$input" == "0" ]]; then break; fi
    done
    
    # 7. 退出时恢复光标
    echo -ne "\033[?25h"
}

# ================= 4. 控制菜单 =================
start_service_quiet() { nohup "$0" --daemon >/dev/null 2>&1 & echo $! > "$PID_FILE"; }
stop_service_quiet() { if [[ -f "$PID_FILE" ]]; then kill $(cat "$PID_FILE") 2>/dev/null; rm -f "$PID_FILE"; fi; }

show_menu() {
    clear; create_default_config; source "$CONF_FILE" 2>/dev/null
    echo -e "${CYAN}========== Traffic Balancer v4.8 ==========${PLAIN}"
    echo -e "  1. 启动服务"
    echo -e "  2. 停止服务"
    echo -e "  3. ${YELLOW}实时监控 (无闪烁)${PLAIN}"
    echo -e "  0. 退出"
    read -p " 选择: " choice
    case $choice in
        1) start_service_quiet; echo -e "${GREEN}启动成功${PLAIN}"; sleep 1 ;;
        2) stop_service_quiet; echo -e "${GREEN}已停止${PLAIN}"; sleep 1 ;;
        3) view_dashboard ;;
        0) exit 0 ;;
        *) ;;
    esac
}

if [[ "$1" == "--daemon" ]]; then
    run_daemon
else
    # 自动格式修复 (防止 Windows 换行符报错)
    sed -i 's/\r$//' "$0" 2>/dev/null
    while true; do show_menu; done
fi
EOF

sed -i 's/\r$//' tb_manager.sh
chmod +x tb_manager.sh
./tb_manager.sh
