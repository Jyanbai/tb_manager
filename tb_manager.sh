#!/usr/bin/env bash
# shellcheck disable=SC1090
#
# tb_manager.sh - v5.0
# 支持 curl 一键启动 + 自动安装 tb 命令
#

set -u

VERSION="5.0"
SCRIPT_SOURCE_URL="https://raw.githubusercontent.com/Jyanbai/tb_manager/main/tb_manager.sh"
SCRIPT_DIR="${HOME}/.tb_manager"
SCRIPT_PATH="${SCRIPT_DIR}/tb_manager.sh"
CONF_FILE="${SCRIPT_DIR}/traffic_balancer.conf"
LOG_FILE="${SCRIPT_DIR}/traffic_balancer.log"
PID_FILE="/tmp/traffic_balancer.pid"
STATUS_FILE="/tmp/tb_status"

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
CYAN="\033[36m"
PLAIN="\033[0m"

UA_LIST=(
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0.0.0 Safari/537.36"
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Chrome/119.0.0.0 Safari/537.36"
)

DOWNLOAD_URLS=(
  "https://speed.cloudflare.com/__down?bytes=50000000"
  "http://speedtest.tele2.net/1GB.zip"
  "http://speedtest.sfo2.digitalocean.com/1gb.test"
)

ensure_runtime_dir() {
  mkdir -p "$SCRIPT_DIR"
}

create_default_config() {
  ensure_runtime_dir
  if [[ ! -f "$CONF_FILE" ]]; then
    cat >"$CONF_FILE" <<CONFIG_EOF
TARGET_RATIO=1.00
RATIO_TOLERANCE=0.30
MIN_SPEED_KB=100
MAX_SPEED_KB=7000
NETWORK_INTERFACE=""
DAILY_MIN_GB=1
DAILY_MAX_GB=5
RUN_MODE="normal"
CONFIG_EOF
  fi
}

load_config() {
  create_default_config
  # shellcheck source=/dev/null
  source "$CONF_FILE"
}

daemon_log() {
  ensure_runtime_dir
  echo "[$(date '+%F %T')] $*" >>"$LOG_FILE"
}

detect_interface() {
  if [[ -n "${NETWORK_INTERFACE:-}" ]]; then
    echo "$NETWORK_INTERFACE"
    return
  fi
  ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -1
}

is_service_running() {
  [[ -f "$PID_FILE" ]] || return 1
  local pid
  pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null
}

run_daemon() {
  load_config

  local iface
  iface="$(detect_interface)"
  if [[ -z "$iface" ]]; then
    daemon_log "错误: 无法检测网卡"
    exit 1
  fi

  : >"$STATUS_FILE"

  local today_limit_gb=$((DAILY_MIN_GB + RANDOM % (DAILY_MAX_GB - DAILY_MIN_GB + 1)))
  daemon_log "启动 v${VERSION} | 接口:${iface} | 目标:${TARGET_RATIO} | 限速:${MAX_SPEED_KB}KB/s"

  get_bytes() {
    grep "$iface:" /proc/net/dev | awk '{print $2, $10}'
  }

  local prev_rx prev_tx prev_time
  read -r prev_rx prev_tx <<<"$(get_bytes)"
  prev_time="$(date +%s)"

  local curl_pid=""
  local is_paused=false
  local today_bytes=0
  local current_day
  current_day="$(date +%d)"

  cleanup_exit() {
    [[ -n "$curl_pid" ]] && kill "$curl_pid" 2>/dev/null || true
    rm -f "$STATUS_FILE"
    exit 0
  }

  trap cleanup_exit SIGTERM SIGINT SIGQUIT SIGHUP

  while true; do
    if [[ "$RUN_MODE" == "random" && "$is_paused" == "false" && -z "$curl_pid" ]]; then
      if ((RANDOM % 10 < 3)); then
        sleep $((10 + RANDOM % 50))
      fi
    fi

    sleep 3

    local now_day
    now_day="$(date +%d)"
    if [[ "$now_day" != "$current_day" ]]; then
      current_day="$now_day"
      today_bytes=0
      today_limit_gb=$((DAILY_MIN_GB + RANDOM % (DAILY_MAX_GB - DAILY_MIN_GB + 1)))
    fi

    local curr_rx curr_tx curr_time dt drx dtx
    read -r curr_rx curr_tx <<<"$(get_bytes)"
    curr_time="$(date +%s)"
    dt=$((curr_time - prev_time))
    ((dt <= 0)) && continue

    drx=$((curr_rx - prev_rx))
    dtx=$((curr_tx - prev_tx))

    if [[ "$is_paused" == "false" ]]; then
      today_bytes=$((today_bytes + drx))
    fi

    local rx_rate tx_rate curr_ratio
    rx_rate=$((drx / dt))
    tx_rate=$((dtx / dt))

    if ((curr_tx > 0)); then
      curr_ratio="$(awk -v r="$curr_rx" -v t="$curr_tx" 'BEGIN {printf "%.2f", r/t}')"
    else
      curr_ratio="0"
    fi

    local limit_bytes limit_reached today_gb
    limit_bytes=$((today_limit_gb * 1024 * 1024 * 1024))
    limit_reached=$((today_bytes >= limit_bytes ? 1 : 0))
    today_gb="$(awk -v b="$today_bytes" 'BEGIN {printf "%.2f", b/1073741824}')"

    {
      echo "RX_RATE=$rx_rate"
      echo "TX_RATE=$tx_rate"
      echo "CURR_RATIO=$curr_ratio"
      echo "TARGET=$TARGET_RATIO"
      echo "TODAY_GB=$today_gb"
      echo "LIMIT_GB=$today_limit_gb"
      echo "LIMIT_REACHED=$limit_reached"
      echo "RUN_MODE=\"$RUN_MODE\""
    } >"$STATUS_FILE"

    if ((limit_reached == 1)); then
      if [[ "$is_paused" == "false" ]]; then
        [[ -n "$curl_pid" ]] && kill "$curl_pid" 2>/dev/null || true
        curl_pid=""
        is_paused=true
        daemon_log "今日限额达标, 暂停下载"
      fi

      prev_rx="$curr_rx"
      prev_tx="$curr_tx"
      prev_time="$curr_time"
      continue
    fi

    local tx_kbps target_kbps upper is_over limit_k
    tx_kbps=$((tx_rate / 1024))
    target_kbps="$(awk -v tx="$tx_kbps" -v r="$TARGET_RATIO" 'BEGIN {print int(tx * r)}')"
    upper="$(awk -v r="$TARGET_RATIO" -v t="$RATIO_TOLERANCE" 'BEGIN {print r + t}')"
    is_over="$(awk -v c="$curr_ratio" -v u="$upper" 'BEGIN {print (c>u)?1:0}')"

    if ((is_over == 1)); then
      if [[ "$is_paused" == "false" ]]; then
        [[ -n "$curl_pid" ]] && kill "$curl_pid" 2>/dev/null || true
        curl_pid=""
        is_paused=true
        daemon_log "暂停: 比例过高"
      fi
    else
      if [[ "$is_paused" == "true" || -z "$curl_pid" || ! -d "/proc/$curl_pid" ]]; then
        local url ua
        is_paused=false
        url="${DOWNLOAD_URLS[$((RANDOM % ${#DOWNLOAD_URLS[@]}))]}"
        ua="${UA_LIST[$((RANDOM % ${#UA_LIST[@]}))]}"

        if [[ "$url" == *"?"* ]]; then
          url="${url}&rand=${RANDOM}"
        else
          url="${url}?rand=${RANDOM}"
        fi

        limit_k="$target_kbps"
        ((limit_k < MIN_SPEED_KB)) && limit_k=$MIN_SPEED_KB
        ((limit_k > MAX_SPEED_KB)) && limit_k=$MAX_SPEED_KB

        curl -s -o /dev/null -A "$ua" --limit-rate "${limit_k}k" -L "$url" &
        curl_pid=$!
      fi
    fi

    prev_rx="$curr_rx"
    prev_tx="$curr_tx"
    prev_time="$curr_time"
  done
}

human_speed() {
  local num=${1:-0}
  if ((num > 1048576)); then
    awk -v n="$num" 'BEGIN {printf "%.2f MB/s", n/1048576}'
  else
    awk -v n="$num" 'BEGIN {printf "%.2f KB/s", n/1024}'
  fi
}

view_dashboard() {
  clear
  echo -ne "\033[?25l"

  while true; do
    local rx_rate=0 tx_rate=0 curr_ratio=0 today_gb=0 limit_reached=0 limit_gb=0 target="-"
    if [[ -f "$STATUS_FILE" ]]; then
      # shellcheck source=/dev/null
      source "$STATUS_FILE" 2>/dev/null || true
      rx_rate=${RX_RATE:-0}
      tx_rate=${TX_RATE:-0}
      curr_ratio=${CURR_RATIO:-0}
      target=${TARGET:-"-"}
      today_gb=${TODAY_GB:-0}
      limit_reached=${LIMIT_REACHED:-0}
      limit_gb=${LIMIT_GB:-0}
    fi

    echo -ne "\033[H"
    echo -e "${CYAN}========== Traffic Balancer v${VERSION} ==========${PLAIN}"
    if is_service_running; then
      echo -e "  状态: ${GREEN}运行中 (PID: $(cat "$PID_FILE"))${PLAIN}"
    else
      echo -e "  状态: ${RED}未运行${PLAIN}"
    fi
    echo -e "  ⬇️  下载: ${GREEN}$(human_speed "$rx_rate")${PLAIN}"
    echo -e "  ⬆️  上传: ${BLUE}$(human_speed "$tx_rate")${PLAIN}"
    echo -e "  📊 比例: ${YELLOW}${curr_ratio} : 1${PLAIN} (目标 ${target})"

    if ((limit_reached == 1)); then
      echo -e "  🛑 今日: ${RED}${today_gb} / ${limit_gb} GB (暂停)${PLAIN}"
    else
      echo -e "  📅 今日: ${GREEN}${today_gb} / ${limit_gb} GB${PLAIN}"
    fi

    echo -e "${CYAN}===========================================${PLAIN}"
    echo -e "  按 ${RED}0${PLAIN} 退出监控"
    echo -ne "\033[0J"

    local input=""
    read -r -t 1 -n 1 input || true
    [[ "$input" == "0" ]] && break
  done

  echo -ne "\033[?25h"
}

start_service() {
  if is_service_running; then
    echo -e "${YELLOW}服务已在运行中${PLAIN}"
    return
  fi

  nohup "$SCRIPT_PATH" --daemon >/dev/null 2>&1 &
  echo "$!" >"$PID_FILE"
  echo -e "${GREEN}启动成功${PLAIN}"
}

stop_service() {
  if ! is_service_running; then
    rm -f "$PID_FILE"
    echo -e "${YELLOW}服务未运行${PLAIN}"
    return
  fi

  kill "$(cat "$PID_FILE")" 2>/dev/null || true
  rm -f "$PID_FILE"
  echo -e "${GREEN}已停止${PLAIN}"
}

install_tb_command() {
  ensure_runtime_dir

  if [[ -f "${BASH_SOURCE[0]}" && "${BASH_SOURCE[0]}" != /dev/fd/* ]]; then
    cp "${BASH_SOURCE[0]}" "$SCRIPT_PATH"
  else
    if ! command -v curl >/dev/null 2>&1; then
      echo -e "${RED}安装失败: 缺少 curl${PLAIN}"
      return 1
    fi

    if ! curl -fsSL "$SCRIPT_SOURCE_URL" -o "$SCRIPT_PATH"; then
      echo -e "${RED}下载脚本失败，请检查网络${PLAIN}"
      return 1
    fi
  fi

  chmod +x "$SCRIPT_PATH"

  local launcher_dir="${HOME}/.local/bin"
  local launcher_path="${launcher_dir}/tb"
  mkdir -p "$launcher_dir"

  cat >"$launcher_path" <<LAUNCHER_EOF
#!/usr/bin/env bash
exec "${SCRIPT_PATH}" "\$@"
LAUNCHER_EOF
  chmod +x "$launcher_path"

  if [[ ":$PATH:" != *":${launcher_dir}:"* ]]; then
    echo -e "${YELLOW}提示: 当前 PATH 不包含 ${launcher_dir}${PLAIN}"
    echo "请执行: echo 'export PATH=\"${launcher_dir}:\$PATH\"' >> ~/.bashrc && source ~/.bashrc"
  fi

  return 0
}

show_menu() {
  load_config
  clear
  echo -e "${CYAN}========== Traffic Balancer v${VERSION} ==========${PLAIN}"
  echo -e "  1. 启动服务"
  echo -e "  2. 停止服务"
  echo -e "  3. 实时监控"
  echo -e "  0. 退出"

  local choice
  read -r -p " 选择: " choice

  case "$choice" in
    1) start_service; sleep 1 ;;
    2) stop_service; sleep 1 ;;
    3) view_dashboard ;;
    0) exit 0 ;;
    *) ;;
  esac
}

main() {
  case "${1:-}" in
    --daemon)
      run_daemon
      ;;
    --no-install)
      while true; do
        show_menu
      done
      ;;
    *)
      if install_tb_command; then
        echo -e "${GREEN}安装完成：可直接输入 tb 启动。${PLAIN}"
      else
        echo -e "${YELLOW}安装步骤未完成，将继续当前会话运行。${PLAIN}"
      fi

      while true; do
        show_menu
      done
      ;;
  esac
}

main "$@"
