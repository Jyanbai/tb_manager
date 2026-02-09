cat > tb_manager.sh << 'EOF'
#!/bin/bash
#
# tb_manager.sh - Traffic Balancer Evolution (v4.5 Stealth Edition)
#

# ================= 基礎配置 =================
CONF_FILE="./traffic_balancer.conf"
PID_FILE="/tmp/traffic_balancer.pid"
LOG_FILE="./traffic_balancer.log"
STATUS_FILE="/tmp/tb_status"

# ================= 顏色定義 =================
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"
PURPLE="\033[35m"
PLAIN="\033[0m"

# ================= 偽裝資源庫 (v4.5 新增) =================
# 隨機 User-Agent 庫 (模擬真實設備)
UA_LIST=(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/115.0"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/118.0.0.0 Safari/537.36"
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36"
)

# 隨機 Referer 庫 (模擬來源)
REF_LIST=(
    "https://www.google.com/"
    "https://www.bing.com/"
    "https://duckduckgo.com/"
    "https://www.baidu.com/"
    "https://www.youtube.com/"
    "https://www.facebook.com/"
)

# ================= 下載源資源庫 =================
# 國外源 (Global)
URLS_GLOBAL=(
    "https://speed.cloudflare.com/__down?bytes=50000000"
    "http://speedtest.tele2.net/1GB.zip"
    "http://mirror.lease-web.net/1000mb.bin"
    "http://ipv4.download.thinkbroadband.com/1GB.zip"
    "http://speedtest-nyc1.digitalocean.com/1gb.test"
    "http://speedtest.sfo2.digitalocean.com/1gb.test"
    "http://speedtest.tokyo2.linode.com/100MB-tokyo2.bin"
    "https://proof.ovh.net/files/1Gb.dat"
    "http://speedtest.belwue.net/1G"
    "http://speedtest.kakao.com/download/test.mp4"
)
# 国内源 (CN)
URLS_CN=(
    "https://mirrors.aliyun.com/centos/7/isos/x86_64/CentOS-7-x86_64-Minimal-2009.iso"
    "https://mirrors.cloud.tencent.com/centos/7/isos/x86_64/CentOS-7-x86_64-Minimal-2009.iso"
    "https://mirrors.163.com/centos/7/isos/x86_64/CentOS-7-x86_64-Minimal-2009.iso"
    "https://mirrors.huaweicloud.com/centos/7/isos/x86_64/CentOS-7-x86_64-Minimal-2009.iso"
    "https://mirrors.ustc.edu.cn/centos/7/isos/x86_64/CentOS-7-x86_64-Minimal-2009.iso"
    "https://mirrors.tuna.tsinghua.edu.cn/centos/7/isos/x86_64/CentOS-7-x86_64-Minimal-2009.iso"
    "https://mirrors.bfsu.edu.cn/centos/7/isos/x86_64/CentOS-7-x86_64-Minimal-2009.iso"
    "https://mirrors.hit.edu.cn/centos/7/isos/x86_64/CentOS-7-x86_64-Minimal-2009.iso"
    "https://mirrors.nju.edu.cn/centos/7/isos/x86_64/CentOS-7-x86_64-Minimal-2009.iso"
    "https://mirrors.zju.edu.cn/centos/7/isos/x86_64/CentOS-7-x86_64-Minimal-2009.iso"
)

# ================= 核心：生成默認配置 =================
create_default_config() {
    if [[ ! -f "$CONF_FILE" ]]; then
        cat > "$CONF_FILE" << CONFIG_EOF
# 流量平衡器配置文件 v4.5
TARGET_RATIO=1.5
RATIO_TOLERANCE=0.3
MIN_SPEED_KB=100
MAX_SPEED_KB=5000
NETWORK_INTERFACE=""
DAILY_LIMIT_GB=4
RUN_MODE="normal"  # normal/random
REGION_MODE="global"
SMART_SCHEDULE="off" # on/off (潮汐模式)
DOWNLOAD_URLS=(
    "https://speed.cloudflare.com/__down?bytes=50000000"
    "http://speedtest.tele2.net/1GB.zip"
)
CONFIG_EOF
    fi
}

# ================= 核心：後台服務邏輯 =================
run_daemon() {
    source "$CONF_FILE"
    
    daemon_log() { echo "[$(date '+%F %T')] $*" >> "$LOG_FILE"; }
    detect_interface() {
        if [[ -n "$NETWORK_INTERFACE" ]]; then echo "$NETWORK_INTERFACE"; return; fi
        ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -1
    }

    IFACE=$(detect_interface)
    if [[ -z "$IFACE" ]]; then daemon_log "錯誤: 無法檢測網卡"; exit 1; fi

    daemon_log "啟動 v4.5 隱匿模式 | 接口: $IFACE | 潮汐: $SMART_SCHEDULE"

    get_bytes() { grep "$IFACE:" /proc/net/dev | awk '{print $2, $10}'; }
    
    read -r PREV_RX PREV_TX <<< "$(get_bytes)"
    PREV_TIME=$(date +%s)
    CURL_PID=""
    IS_PAUSED=false
    TODAY_BYTES=0
    CURRENT_DAY=$(date +%d)
    
    # 用於顯示當前偽裝狀態
    CURRENT_UA="Default"
    CURRENT_MODE_LABEL="標準"

    # 清理函數
    cleanup_exit() {
        if [[ -n "$CURL_PID" ]]; then kill -9 "$CURL_PID" 2>/dev/null; fi
        pkill -P $$ 2>/dev/null
        rm -f "$PID_FILE" "$STATUS_FILE"
        exit 0
    }
    trap cleanup_exit SIGTERM SIGINT SIGQUIT SIGHUP

    while true; do
        # 1. 隨機間隔邏輯
        if [[ "$RUN_MODE" == "random" ]] && [[ "$IS_PAUSED" == "false" ]] && [[ -z "$CURL_PID" ]]; then
             if [ $((RANDOM % 10)) -lt 3 ]; then
                 SLEEP_T=$((10 + RANDOM % 50))
                 daemon_log "隨機休眠: ${SLEEP_T}秒"
                 sleep $SLEEP_T
             fi
        fi

        sleep 3
        
        # 2. 日期變更
        NOW_DAY=$(date +%d)
        if [[ "$NOW_DAY" != "$CURRENT_DAY" ]]; then
            CURRENT_DAY=$NOW_DAY
            TODAY_BYTES=0
            daemon_log "新的一天，流量計數重置"
        fi

        # 3. 潮汐調度 (Smart Schedule) - v4.5 核心
        REAL_MAX_SPEED=$MAX_SPEED_KB
        CURRENT_HOUR=$(date +%H)
        CURRENT_HOUR=${CURRENT_HOUR#0} # 去除前導0
        
        if [[ "$SMART_SCHEDULE" == "on" ]]; then
            # 夜間模式 (01:00 - 09:00) 全速
            if [[ $CURRENT_HOUR -ge 1 && $CURRENT_HOUR -lt 9 ]]; then
                CURRENT_MODE_LABEL="🌙 夜間全速"
                REAL_MAX_SPEED=$MAX_SPEED_KB
            else
                # 日間模式 (09:00 - 01:00) 半速
                CURRENT_MODE_LABEL="☀️ 日間避峰"
                REAL_MAX_SPEED=$((MAX_SPEED_KB / 2))
                # 確保不低於最低速度
                [[ $REAL_MAX_SPEED -lt $MIN_SPEED_KB ]] && REAL_MAX_SPEED=$MIN_SPEED_KB
            fi
        else
             CURRENT_MODE_LABEL="⚡ 固定全速"
        fi

        read -r CURR_RX CURR_TX <<< "$(get_bytes)"
        CURR_TIME=$(date +%s)
        DT=$((CURR_TIME - PREV_TIME))
        [ $DT -le 0 ] && continue
        
        DRX=$((CURR_RX - PREV_RX))
        DTX=$((CURR_TX - PREV_TX))
        
        if [[ "$IS_PAUSED" == "false" ]]; then TODAY_BYTES=$((TODAY_BYTES + DRX)); fi
        
        RX_RATE=$(( DRX / DT ))
        TX_RATE=$(( DTX / DT ))
        
        if [[ $CURR_TX -gt 0 ]]; then
            CURR_RATIO=$(awk -v r="$CURR_RX" -v t="$CURR_TX" 'BEGIN {printf "%.2f", r/t}')
        else
            CURR_RATIO=0
        fi
        
        LIMIT_BYTES=$((DAILY_LIMIT_GB * 1024 * 1024 * 1024))
        LIMIT_REACHED=$(( TODAY_BYTES >= LIMIT_BYTES ? 1 : 0 ))

        TODAY_GB=$(awk -v b="$TODAY_BYTES" 'BEGIN {printf "%.2f", b/1073741824}')
        {
            echo "RX_RATE=$RX_RATE"
            echo "TX_RATE=$TX_RATE"
            echo "CURR_RATIO=$CURR_RATIO"
            echo "TARGET=$TARGET_RATIO"
            echo "TODAY_GB=$TODAY_GB"
            echo "LIMIT_GB=$DAILY_LIMIT_GB"
            echo "LIMIT_REACHED=$LIMIT_REACHED"
            echo "MODE_LABEL=$CURRENT_MODE_LABEL"
            echo "UA_LABEL=${CURRENT_UA:0:25}..." # 截取UserAgent前25字
        } > "$STATUS_FILE"
        
        # 4. 控制邏輯
        if [[ $LIMIT_REACHED -eq 1 ]]; then
            if [[ "$IS_PAUSED" == "false" ]]; then
                if [[ -n "$CURL_PID" ]]; then kill "$CURL_PID" 2>/dev/null; CURL_PID=""; fi
                IS_PAUSED=true; daemon_log "今日達標 ($TODAY_GB GB)，暫停"
            fi
            PREV_RX=$CURR_RX; PREV_TX=$CURR_TX; PREV_TIME=$CURR_TIME; continue
        fi

        TX_KBPS=$((TX_RATE / 1024))
        TARGET_KBPS=$(awk -v tx="$TX_KBPS" -v r="$TARGET_RATIO" 'BEGIN {print int(tx * r)}')
        UPPER=$(awk -v r="$TARGET_RATIO" -v t="$RATIO_TOLERANCE" 'BEGIN {print r + t}')
        SHOULD_PAUSE=$(awk -v c="$CURR_RATIO" -v u="$UPPER" 'BEGIN {if(c > u) print 1; else print 0}')
        
        if [[ "$SHOULD_PAUSE" -eq 1 ]]; then
             if [[ "$IS_PAUSED" == "false" ]]; then
                 if [[ -n "$CURL_PID" ]]; then kill "$CURL_PID" 2>/dev/null; CURL_PID=""; fi
                 IS_PAUSED=true; daemon_log "暫停: 比例 $CURR_RATIO 過高"
             fi
        else
             if [[ "$IS_PAUSED" == "true" ]] || [[ -z "$CURL_PID" ]] || ! kill -0 "$CURL_PID" 2>/dev/null; then
                 IS_PAUSED=false
                 
                 # v4.5 新增：隨機抽取 UA 和 Referer
                 RAND_UA=${UA_LIST[$((RANDOM % ${#UA_LIST[@]}))]}
                 RAND_REF=${REF_LIST[$((RANDOM % ${#REF_LIST[@]}))]}
                 CURRENT_UA="$RAND_UA"
                 
                 URL=${DOWNLOAD_URLS[$((RANDOM % ${#DOWNLOAD_URLS[@]}))]}
                 
                 LIMIT_K=$TARGET_KBPS
                 [[ $LIMIT_K -lt $MIN_SPEED_KB ]] && LIMIT_K=$MIN_SPEED_KB
                 [[ $LIMIT_K -gt $REAL_MAX_SPEED ]] && LIMIT_K=$REAL_MAX_SPEED
                 
                 # 核心：帶偽裝頭的下載
                 curl -s -o /dev/null \
                      -A "$RAND_UA" \
                      -H "Referer: $RAND_REF" \
                      -H "Accept-Language: en-US,en;q=0.9" \
                      --limit-rate "${LIMIT_K}k" \
                      -L "$URL" &
                 CURL_PID=$!
             fi
        fi
        PREV_RX=$CURR_RX; PREV_TX=$CURR_TX; PREV_TIME=$CURR_TIME
    done
}

# ================= 界面函數 =================
human_speed() {
    local num=$1
    if [ $num -gt 1048576 ]; then awk -v n="$num" 'BEGIN {printf "%.2f MB/s", n/1048576}';
    else awk -v n="$num" 'BEGIN {printf "%.2f KB/s", n/1024}'; fi
}

get_status() {
    if [[ -f "$PID_FILE" ]] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo -e "${GREEN}運行中 (PID: $(cat $PID_FILE))${PLAIN}"
        return 0
    else
        echo -e "${RED}未運行${PLAIN}"
        return 1
    fi
}

# ================= 配置嚮導 (v4.5) =================
wizard_config() {
    clear
    echo -e "${CYAN}====== 配置嚮導 (v4.5 Evolution) ======${PLAIN}"
    echo -e "新增特性：User-Agent 隨機偽裝已默認開啟。"
    
    read -p "1. 目標比例 (默認 1.5): " input_ratio
    [[ -z "$input_ratio" ]] && input_ratio="1.5"

    read -p "2. 每日流量限制GB (默認 4): " input_limit
    [[ -z "$input_limit" ]] && input_limit="4"
    
    read -p "3. 最高速度限制KB/s (默認 5000): " input_max
    [[ -z "$input_max" ]] && input_max="5000"

    echo -e "\n4. ${YELLOW}啟用潮汐調度 (Smart Schedule)?${PLAIN}"
    echo -e "   - 開啟後：白天(09-01)降速至50%，深夜(01-09)全速"
    echo -e "   - 關閉後：全天固定最高限速"
    read -p "   請選擇 (y=開啟, n=關閉, 默認n): " input_smart
    if [[ "$input_smart" == "y" ]]; then SMART_VAL="on"; else SMART_VAL="off"; fi

    echo -e "\n5. ${YELLOW}選擇下載源地區:${PLAIN}"
    echo -e "   1. ${GREEN}國外模式${PLAIN} (Cloudflare, Tele2...)"
    echo -e "   2. ${GREEN}國內模式${PLAIN} (阿里, 騰訊, 華為...)"
    read -p "   請選擇 (1/2): " input_region
    
    # 寫入配置
    sed -i "s/^TARGET_RATIO=.*/TARGET_RATIO=$input_ratio/" "$CONF_FILE"
    sed -i "s/^DAILY_LIMIT_GB=.*/DAILY_LIMIT_GB=$input_limit/" "$CONF_FILE"
    sed -i "s/^MAX_SPEED_KB=.*/MAX_SPEED_KB=$input_max/" "$CONF_FILE"
    sed -i "s/^SMART_SCHEDULE=.*/SMART_SCHEDULE=\"$SMART_VAL\"/" "$CONF_FILE"
    
    # 寫入URL
    sed -i '/^DOWNLOAD_URLS=(/,/)/d' "$CONF_FILE"
    sed -i '/^REGION_MODE=/d' "$CONF_FILE"
    echo "REGION_MODE=\"$([ "$input_region" == "2" ] && echo "cn" || echo "global")\"" >> "$CONF_FILE"
    echo "DOWNLOAD_URLS=(" >> "$CONF_FILE"
    if [[ "$input_region" == "2" ]]; then
        for url in "${URLS_CN[@]}"; do echo "    \"$url\"" >> "$CONF_FILE"; done
    else
        for url in "${URLS_GLOBAL[@]}"; do echo "    \"$url\"" >> "$CONF_FILE"; done
    fi
    echo ")" >> "$CONF_FILE"

    echo -e "\n${GREEN}✅ 配置已保存！請重啟服務生效。${PLAIN}"
    read -p "按回車返回..."
}

set_run_mode() {
    clear
    echo -e " 1. ${GREEN}持續運行${PLAIN} (標準)"
    echo -e " 2. ${GREEN}隨機間隔${PLAIN} (模擬真人，隨機休眠)"
    read -p "選擇 (默認 1): " input_mode
    if [[ "$input_mode" == "2" ]]; then
        sed -i 's/^RUN_MODE=.*/RUN_MODE="random"/' "$CONF_FILE"
    else
        sed -i 's/^RUN_MODE=.*/RUN_MODE="normal"/' "$CONF_FILE"
    fi
    echo -e "${GREEN}設置完成，請重啟服務。${PLAIN}"; read -p "按回車返回..."
}

start_service() {
    if get_status | grep -q "運行中"; then echo -e "${YELLOW}已運行！${PLAIN}"; read -p "..." && return; fi
    nohup "$0" --daemon >/dev/null 2>&1 &
    echo $! > "$PID_FILE"
    echo -e "${GREEN}啟動成功${PLAIN}"; sleep 1
}

stop_service() {
    if [[ -f "$PID_FILE" ]]; then
        kill $(cat "$PID_FILE") 2>/dev/null
        rm -f "$PID_FILE"
        echo -e "${GREEN}服務已停止 (無殘留)${PLAIN}"
    else
        echo -e "${RED}未運行${PLAIN}"
    fi
    read -p "..."
}

view_dashboard() {
    clear; echo -e "\033[?25l"
    while true; do
        if [[ -f "$STATUS_FILE" ]]; then source "$STATUS_FILE"; else RX_RATE=0; TX_RATE=0; CURR_RATIO=0; TODAY_GB=0; LIMIT_REACHED=0; MODE_LABEL="-"; UA_LABEL="-"; fi
        echo -e "\033[H\033[2J"
        echo -e "${CYAN}========== Traffic Balancer v4.5 ==========${PLAIN}"
        echo -e "  狀態: $(get_status)"
        echo -e "  偽裝: ${PURPLE}${UA_LABEL}${PLAIN}"
        echo -e "  調度: ${YELLOW}${MODE_LABEL}${PLAIN}"
        echo -e ""
        echo -e "  ⬇️  下載: ${GREEN}$(human_speed ${RX_RATE:-0})${PLAIN}"
        echo -e "  ⬆️  上传: ${BLUE}$(human_speed ${TX_RATE:-0})${PLAIN}"
        echo -e "  📊 比例: ${YELLOW}${CURR_RATIO:-0} : 1${PLAIN}"
        if [[ "$LIMIT_REACHED" -eq 1 ]]; then
            echo -e "  🛑 今日: ${RED}${TODAY_GB} / ${DAILY_LIMIT_GB} GB (暫停)${PLAIN}"
        else
            echo -e "  📅 今日: ${GREEN}${TODAY_GB} / ${DAILY_LIMIT_GB} GB${PLAIN}"
        fi
        echo -e "${CYAN}===========================================${PLAIN}"
        echo -e "  按 ${RED}0${PLAIN} 退出"
        read -t 1 -n 1 input; [[ "$input" == "0" ]] && break
    done
    echo -e "\033[?25h"
}

show_menu() {
    clear; create_default_config; source "$CONF_FILE"
    echo -e "${CYAN}========== Traffic Balancer v4.5 ==========${PLAIN}"
    echo -e "  模式: $([ "$REGION_MODE" == "cn" ] && echo "國內" || echo "國外") | $([ "$SMART_SCHEDULE" == "on" ] && echo "潮汐" || echo "固定") | $([ "$RUN_MODE" == "random" ] && echo "隨機" || echo "持續")"
    echo -e "  ${GREEN}1.${PLAIN} 啟動  ${GREEN}2.${PLAIN} 停止  ${GREEN}3.${PLAIN} 重啟"
    echo -e "  ${GREEN}4.${PLAIN} ${YELLOW}實時監控 (含偽裝詳情)${PLAIN}"
    echo -e "  ${GREEN}5.${PLAIN} 修改配置 (開啟潮汐調度等)"
    echo -e "  ${GREEN}6.${PLAIN} 查看日誌"
    echo -e "  ${GREEN}7.${PLAIN} 運行策略 (持續/隨機間隔)"
    echo -e "  ${RED}0. 退出${PLAIN}"
    echo -e ""
    read -p " 選擇 [0-7]: " choice
    case $choice in
        1) start_service ;; 2) stop_service ;; 3) stop_service; start_service ;;
        4) view_dashboard ;; 5) wizard_config ;; 6) tail -n 20 "$LOG_FILE"; read -p "..." ;;
        7) set_run_mode ;; 0) exit 0 ;; *) ;;
    esac
}

if [[ "$1" == "--daemon" ]]; then run_daemon; else
    if [[ -f "$0" ]]; then sed -i 's/\r$//' "$0" 2>/dev/null; fi
    while true; do show_menu; done
fi
EOF

sed -i 's/\r$//' tb_manager.sh
chmod +x tb_manager.sh
./tb_manager.sh